import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../net/arp.dart';
import '../net/ipv4.dart';
import '../net/local_network.dart';
import '../net/mdns.dart';
import '../net/netbios.dart';
import '../net/oui.dart';
import '../net/ping.dart';
import '../net/prober.dart';
import '../net/ssdp.dart';
import 'device_store.dart';

enum DeviceFilter { all, online, offline, fresh }

/// Runs network scans and holds the device list the UI shows.
class ScanController extends ChangeNotifier {
  ScanController(this._store);

  final DeviceStore _store;
  static const _multicast = MethodChannel('netwho/multicast');

  LocalNetwork? network;
  String? _networkKey;
  String? error;
  bool scanning = false;
  double progress = 0;
  String phase = '';
  DateTime? lastScan;

  /// Online devices from the latest scan plus remembered offline ones.
  List<Device> devices = [];

  bool _cancel = false;
  Timer? _notifyTimer;

  int get onlineCount => devices.where((d) => d.online).length;
  int get newCount => devices.where((d) => d.isNew).length;

  List<Device> filtered(DeviceFilter f, String query) {
    final q = query.trim().toLowerCase();
    return devices.where((d) {
      final keep = switch (f) {
        DeviceFilter.all => true,
        DeviceFilter.online => d.online,
        DeviceFilter.offline => !d.online,
        DeviceFilter.fresh => d.isNew,
      };
      if (!keep) return false;
      if (q.isEmpty) return true;
      return [d.displayName, d.ip, d.mac, d.vendor, d.hostname, d.model, d.type.label]
          .whereType<String>()
          .any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  /// Shows remembered devices for the current network before any scan runs.
  Future<void> loadCached() async {
    try {
      final net = await detectLocalNetwork();
      network = net;
      final arp = await readArpTable();
      _networkKey = _keyFor(net, arp);
      lastScan = _store.lastScan(_networkKey!);
      devices = _store.devicesFor(_networkKey!)..sort(_byIp);
    } catch (_) {}
    notifyListeners();
  }

  void cancel() => _cancel = true;

  /// The current object for [d], which may have been replaced by a scan.
  Device resolve(Device d) {
    for (final x in devices) {
      if (identical(x, d)) return x;
    }
    for (final x in devices) {
      if (x.key == d.key) return x;
    }
    for (final x in devices) {
      if (x.ip == d.ip && (x.mac == null || d.mac == null)) return x;
    }
    return d;
  }

  void setWifiName(String name) {
    network?.wifiName = name;
    notifyListeners();
  }

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    _cancel = false;
    error = null;
    progress = 0;
    phase = 'Finding your network…';
    notifyListeners();

    final mdns = MdnsBrowser();
    try {
      await _multicast.invokeMethod('acquire');
    } catch (_) {} // Only exists on Android.

    try {
      final net = await detectLocalNetwork();
      network = net;
      await VendorLookup.instance.load();
      final started = DateTime.now();

      final live = <String, Device>{};
      Device touch(String ip) => live.putIfAbsent(ip, () => Device(ip: ip)
        ..online = true
        ..lastSeen = started);

      // Remembered devices start greyed out and light up as they answer.
      for (final d in devices) {
        d.online = false;
      }
      final range = net.scanRange;
      phase = 'Scanning ${range.cidr}…';
      notifyListeners();

      final mdnsReady = await mdns.start();
      final mdnsFuture = mdnsReady
          ? mdns.browse(window: const Duration(seconds: 5))
          : Future.value(<String, MdnsInfo>{});
      final upnpFuture = discoverUpnp();

      final hosts = range.hosts.toList();
      var done = 0;
      final usePing = await pingAvailable();
      await runPool<int>(hosts, Platform.isAndroid ? 40 : 64, (addr) async {
        final ip = formatIpv4(addr);
        final r = await probeHost(ip, usePing: usePing);
        if (r != null) {
          touch(ip)
            ..latencyMs = r.latencyMs
            ..openPorts.addAll(r.openPorts);
          _publish(live.values, net);
        }
        done++;
        progress = 0.7 * done / hosts.length;
        _scheduleNotify();
      }, cancelled: () => _cancel);
      if (_cancel) throw _Cancelled();

      phase = 'Identifying devices…';
      progress = 0.72;
      notifyListeners();

      // The ARP table also lists hosts that ignore every probe but still
      // had to answer ARP for the probes to be sent.
      final arp = await readArpTable();
      arp.forEach((ip, mac) {
        final v = parseIpv4(ip);
        if (v != null && range.contains(v)) touch(ip).mac = mac;
      });
      final self = touch(net.ip)
        ..isSelf = true
        ..mac ??= net.mac
        ..latencyMs ??= 0;
      if (Platform.isLinux) self.hostname = Platform.localHostname;
      if (net.gateway != null) touch(net.gateway!).isGateway = true;

      final unicastUpnp = discoverUpnp(
        targets: live.keys.where((ip) => ip != net.ip),
        window: const Duration(milliseconds: 1500),
      );
      final mdnsInfo = await mdnsFuture;
      final upnpInfo = {...await upnpFuture};
      (await unicastUpnp).forEach((ip, info) {
        final prev = upnpInfo[ip];
        if (prev == null || prev.friendlyName == null) upnpInfo[ip] = info;
      });
      progress = 0.8;
      notifyListeners();

      mdnsInfo.forEach((ip, info) {
        final v = parseIpv4(ip);
        if (v == null || !range.contains(v)) return;
        touch(ip)
          ..mdnsName = info.friendlyName ?? info.hostname
          ..hostname ??= info.hostname
          ..mac ??= info.mac
          ..model ??= info.model
          ..services.addAll(info.services);
      });
      upnpInfo.forEach((ip, info) {
        final v = parseIpv4(ip);
        if (v == null || !range.contains(v)) return;
        touch(ip)
          ..upnpName = info.friendlyName
          ..upnpManufacturer = info.manufacturer
          ..model ??= info.model;
      });
      _publish(live.values, net);

      final ips = live.keys.toList();
      final nb = await queryNetbios(ips);
      nb.forEach((ip, info) {
        final d = live[ip];
        if (d == null) return;
        d.netbiosName = info.name;
        d.mac ??= info.mac;
      });
      progress = 0.85;
      notifyListeners();

      // Reverse DNS via the router, then multicast reverse for the rest.
      await runPool<Device>(live.values.toList(), 24, (d) async {
        if (d.hostname != null) return;
        try {
          final r = await InternetAddress(d.ip)
              .reverse()
              .timeout(const Duration(seconds: 2));
          // systemd-resolved answers "_gateway" for the router; not a real name.
          if (r.host != d.ip && !r.host.startsWith('_')) d.hostname = r.host;
        } catch (_) {}
        if (d.hostname == null && mdnsReady) d.hostname = await mdns.reverse(d.ip);
      }, cancelled: () => _cancel);
      if (_cancel) throw _Cancelled();

      for (final d in live.values) {
        d.vendor = VendorLookup.instance.vendorFor(d.mac) ?? d.upnpManufacturer ?? d.vendor;
      }

      progress = 0.95;
      phase = 'Saving…';
      notifyListeners();
      await _merge(net, live.values.toList(), arp, started);
      progress = 1;
    } on _Cancelled {
      error = 'Scan cancelled.';
    } catch (e) {
      error = e is NoNetworkException ? e.toString() : 'Scan failed: $e';
    } finally {
      mdns.stop();
      try {
        await _multicast.invokeMethod('release');
      } catch (_) {}
      _notifyTimer?.cancel();
      scanning = false;
      phase = '';
      notifyListeners();
    }
  }

  /// Folds live results into what we remember about this network.
  Future<void> _merge(
    LocalNetwork net,
    List<Device> live,
    Map<String, String> arp,
    DateTime scannedAt,
  ) async {
    final key = _keyFor(net, arp);
    _networkKey = key;
    final firstScan = !_store.hasNetwork(key);
    final remembered = _store.devicesFor(key);
    final byKey = {for (final d in remembered) d.key: d};
    final byIp = {
      for (final d in remembered)
        if (d.mac == null) d.ip: d,
    };

    for (final d in live) {
      final old = byKey.remove(d.key) ?? byIp.remove(d.ip);
      if (old != null) {
        byKey.remove(old.key);
        d.inheritFrom(old);
        d.isNew = false;
      } else {
        d.firstSeen = scannedAt;
        d.isNew = !firstScan;
      }
      d.online = true;
      d.lastSeen = scannedAt;
    }
    final offline = byKey.values.toList()
      ..forEach((d) {
        d.online = false;
        d.isNew = false;
      });

    devices = [...live, ...offline]..sort(_byIp);
    lastScan = scannedAt;
    await _store.save(key, devices, scannedAt: scannedAt);
  }

  String _keyFor(LocalNetwork net, Map<String, String> arp) {
    final gwMac = net.gateway == null ? null : arp[net.gateway];
    return gwMac != null ? 'gw:$gwMac' : net.key;
  }

  /// Streams partial results to the list while the sweep is still running.
  void _publish(Iterable<Device> live, LocalNetwork net) {
    final byIp = {for (final d in devices) d.ip: d};
    // Remembered entries are only marked online here; matching them properly
    // (by MAC) happens in _merge once the scan has finished.
    for (final d in live) {
      if (d.ip == net.gateway) d.isGateway = true;
      final existing = byIp[d.ip];
      if (existing == null) {
        byIp[d.ip] = d;
      } else if (existing != d) {
        existing
          ..online = true
          ..latencyMs = d.latencyMs;
      }
    }
    devices = byIp.values.toList()..sort(_byIp);
  }

  void _scheduleNotify() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 250), notifyListeners);
  }

  // ---- Edits the user makes to a device ----

  Future<void> updateDevice(Device d, void Function(Device d) change) async {
    change(d);
    notifyListeners();
    await _save();
  }

  Future<void> forget(Device d) async {
    devices.remove(d);
    notifyListeners();
    await _save();
  }

  Future<void> forgetAll() async {
    final key = _networkKey;
    devices = devices.where((d) => d.online).toList();
    for (final d in devices) {
      d.customName = null;
      d.typeOverride = null;
      d.notes = null;
      d.isNew = false;
    }
    if (key != null) await _store.forgetNetwork(key);
    notifyListeners();
  }

  /// Marks every device as seen, clearing the "new" badges.
  void acknowledgeNew() {
    for (final d in devices) {
      d.isNew = false;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final key = _networkKey;
    if (key != null) await _store.save(key, devices);
  }

  static int _byIp(Device a, Device b) => a.sortKey.compareTo(b.sortKey);
}

class _Cancelled implements Exception {}
