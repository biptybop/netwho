import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

/// What a host advertised over mDNS / Bonjour.
class MdnsInfo {
  String? hostname;
  String? friendlyName;
  String? model;

  /// Some hosts (Linux _workstation) put their MAC in the instance name.
  String? mac;
  final Set<String> services = {};
}

/// Service types worth asking for directly, since not every device answers
/// the "list all services" meta-query.
const _commonTypes = [
  '_http._tcp', '_googlecast._tcp', '_airplay._tcp', '_raop._tcp',
  '_ipp._tcp', '_ipps._tcp', '_printer._tcp', '_pdl-datastream._tcp',
  '_scanner._tcp', '_uscan._tcp', '_smb._tcp', '_afpovertcp._tcp',
  '_adisk._tcp', '_workstation._tcp', '_device-info._tcp',
  '_companion-link._tcp', '_spotify-connect._tcp', '_hap._tcp',
  '_sonos._tcp', '_ssh._tcp', '_sftp-ssh._tcp', '_amzn-wplay._tcp',
  '_androidtvremote2._tcp', '_matter._tcp', '_matterc._udp',
  '_esphomelib._tcp', '_hue._tcp', '_nvstream._tcp', '_home-assistant._tcp',
  '_rfb._tcp', '_touch-able._tcp', '_mediaremotetv._tcp', '_sleep-proxy._udp',
  '_plexmediasvr._tcp', '_daap._tcp', '_raop._tcp', '_viziocast._tcp',
  '_roku._tcp', '_ecp._tcp', '_nanoleafapi._tcp', '_miio._udp', '_elg._tcp',
];

class MdnsBrowser {
  MDnsClient? _client;

  Future<bool> start() async {
    try {
      final client = MDnsClient(
        rawDatagramSocketFactory: (host, int port,
                {bool reuseAddress = true, bool reusePort = false, int ttl = 1}) =>
            RawDatagramSocket.bind(host, port,
                reuseAddress: true,
                // Dart can't set SO_REUSEPORT on Android; reuseAddress is
                // enough there to share 5353 with the system resolver.
                reusePort: reusePort && !Platform.isAndroid,
                ttl: ttl),
      );
      await client.start(
        interfacesFactory: (type) async => (await NetworkInterface.list(
          includeLinkLocal: false,
          type: type,
        ))
            .where((i) => !i.name.startsWith('tailscale') && !i.name.startsWith('tun'))
            .toList(),
      );
      _client = client;
      return true;
    } catch (_) {
      return false;
    }
  }

  void stop() {
    _client?.stop();
    _client = null;
  }

  /// Browses for services for roughly [window] and returns what each IP
  /// advertised.
  Future<Map<String, MdnsInfo>> browse({
    Duration window = const Duration(seconds: 4),
  }) async {
    final client = _client;
    final found = <String, MdnsInfo>{};
    if (client == null) return found;

    final types = <String>{for (final t in _commonTypes) '$t.local'};
    try {
      await for (final ptr in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer('_services._dns-sd._udp.local'),
            timeout: const Duration(milliseconds: 1500),
          )
          .timeout(const Duration(seconds: 2), onTimeout: (s) => s.close())) {
        types.add(ptr.domainName);
      }
    } catch (_) {}

    final deadline = DateTime.now().add(window);
    Duration left() {
      final d = deadline.difference(DateTime.now());
      return d.isNegative ? const Duration(milliseconds: 1) : d;
    }

    Future<void> resolveInstance(String type, String instance) async {
      String? target;
      final txt = <String, String>{};
      await Future.wait([
        _collect<SrvResourceRecord>(client, ResourceRecordQuery.service(instance), left())
            .then((srv) => target = srv.isEmpty ? null : srv.first.target),
        _collect<TxtResourceRecord>(client, ResourceRecordQuery.text(instance), left())
            .then((recs) {
          for (final r in recs) {
            for (final entry in r.text.split('\n')) {
              final eq = entry.indexOf('=');
              if (eq > 0) txt[entry.substring(0, eq).toLowerCase()] = entry.substring(eq + 1);
            }
          }
        }),
      ]);
      if (target == null) return;
      final addrs = await _collect<IPAddressResourceRecord>(
          client, ResourceRecordQuery.addressIPv4(target!), left());
      var label = _instanceLabel(instance, type);
      String? mac;
      final macInName = label == null ? null : _macSuffix.firstMatch(label);
      if (macInName != null) {
        mac = macInName.group(1)!.toLowerCase();
        label = label!.substring(0, macInName.start).trim();
      }
      // AirPlay audio names look like "A1B2C3D4E5F6@Living Room".
      final raop = label == null ? null : RegExp(r'^([0-9A-Fa-f]{12})@(.+)$').firstMatch(label);
      if (raop != null) {
        final hex = raop.group(1)!.toLowerCase();
        mac ??= [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
        label = raop.group(2);
      }
      final host = _stripLocal(target!);
      final isCast = type.startsWith('_googlecast.');
      for (final a in addrs) {
        final info = found.putIfAbsent(a.address.address, MdnsInfo.new);
        if (!_looksGenerated(host)) info.hostname ??= host;
        info.mac ??= mac;
        if (!type.contains('._sub.')) info.services.add(_stripLocal(type));
        // Cast uses "fn"; Fire TV puts the owner's name in "n".
        final fn = txt['fn'] ?? (type.startsWith('_amzn-wplay.') ? txt['n'] : null);
        if (fn != null && fn.isNotEmpty) {
          info.friendlyName = fn;
        } else if (label != null && _looksFriendly(type) && !_looksGenerated(label)) {
          info.friendlyName ??= label;
        }
        // "md" means different things per service; only trust it for Cast.
        final md = (isCast ? txt['md'] : null) ?? txt['model'] ?? txt['ty'] ?? txt['usb_mdl'];
        if (md != null && md.isNotEmpty) info.model ??= md;
      }
    }

    await Future.wait(types.map((type) async {
      final instances =
          await _collect<PtrResourceRecord>(client, ResourceRecordQuery.serverPointer(type), left());
      await Future.wait(instances.map((p) => resolveInstance(type, p.domainName)));
    }));
    return found;
  }

  /// Multicast reverse lookup: many Apple and Linux devices answer these even
  /// when the router's DNS has never heard of them.
  Future<String?> reverse(String ip) async {
    final client = _client;
    if (client == null) return null;
    final name = '${ip.split('.').reversed.join('.')}.in-addr.arpa';
    final recs = await _collect<PtrResourceRecord>(
        client, ResourceRecordQuery.serverPointer(name), const Duration(milliseconds: 1200));
    return recs.isEmpty ? null : _stripLocal(recs.first.domainName);
  }
}

Future<List<T>> _collect<T extends ResourceRecord>(
  MDnsClient client,
  ResourceRecordQuery query,
  Duration timeout,
) async {
  final out = <T>[];
  try {
    await for (final r in client
        .lookup<T>(query, timeout: timeout)
        .timeout(timeout + const Duration(milliseconds: 300), onTimeout: (s) => s.close())) {
      out.add(r);
    }
  } catch (_) {}
  return out;
}

final _macSuffix = RegExp(r'\s*\[([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})\]\s*$');

/// UUIDs, long hex strings and bare numbers that some services (Cast, KDE
/// Connect) use as host or instance names — useless to a person.
bool _looksGenerated(String name) {
  if (name.contains(':')) return true; // e.g. "amzn.dmgr:6F22…"
  final n = name.replaceAll('-', '');
  if (RegExp(r'^\d+$').hasMatch(n)) return true;
  return n.length >= 12 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(n);
}

String _stripLocal(String name) {
  var n = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
  if (n.endsWith('.local')) n = n.substring(0, n.length - 6);
  return n;
}

String? _instanceLabel(String instance, String type) {
  final suffix = '.$type';
  if (!instance.endsWith(suffix)) return null;
  return instance.substring(0, instance.length - suffix.length).replaceAll(r'\032', ' ');
}

/// Instance names on these services are usually the name the owner gave it.
bool _looksFriendly(String type) => const [
      '_airplay', '_raop', '_ipp', '_ipps', '_printer', '_companion-link',
      '_spotify-connect', '_hap', '_sonos', '_smb', '_adisk', '_workstation',
      '_device-info', '_androidtvremote2', '_roku', '_viziocast',
    ].any((t) => type.startsWith('$t.'));
