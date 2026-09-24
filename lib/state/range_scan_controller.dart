import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../net/arp.dart';
import '../net/ipv4.dart';
import '../net/netbios.dart';
import '../net/oui.dart';
import '../net/ping.dart';
import '../net/prober.dart';

/// One responding address from a range scan.
class RangeHost {
  RangeHost(this.ip, this.latencyMs, this.openPorts);

  final String ip;
  final double? latencyMs;
  final Set<int> openPorts;
  String? hostname;
  String? netbiosName;
  String? mac;
  String? vendor;

  String get name => netbiosName ?? hostname ?? '';
}

const _kRecentRanges = 'recentRanges';
const _kProbePorts = 'rangeProbePorts';

/// Scans arbitrary address ranges, e.g. other subnets at work. Kept apart
/// from the home-network scan: nothing here is remembered as a device.
/// Lives for the whole app so a scan keeps running if you leave the page.
class RangeScanController extends ChangeNotifier {
  SharedPreferences? _prefs;

  List<String> recent = [];
  List<RangeHost> hosts = [];
  bool scanning = false;
  double progress = 0;
  int scanned = 0;
  int total = 0;
  String? lastQuery;
  DateTime? finishedAt;
  Duration? elapsed;
  bool cancelled = false;
  bool _cancel = false;

  /// Try common TCP ports as well as ping, to catch hosts that block ping.
  /// Off by default: ping-only sweeps are faster and quieter.
  bool probePorts = false;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      recent = _prefs!.getStringList(_kRecentRanges) ?? [];
      probePorts = _prefs!.getBool(_kProbePorts) ?? false;
    } catch (_) {}
  }

  void setProbePorts(bool v) {
    probePorts = v;
    _prefs?.setBool(_kProbePorts, v);
    notifyListeners();
  }

  void cancel() => _cancel = true;

  void forgetRecent(String q) {
    recent.remove(q);
    _prefs?.setStringList(_kRecentRanges, recent);
    notifyListeners();
  }

  Future<void> scan(String query, List<int> addresses) async {
    if (scanning) return;
    scanning = true;
    _cancel = false;
    cancelled = false;
    hosts = [];
    scanned = 0;
    total = addresses.length;
    progress = 0;
    lastQuery = query.trim();
    finishedAt = null;
    _remember(lastQuery!);
    notifyListeners();

    final sw = Stopwatch()..start();
    final found = <String, RangeHost>{};
    Timer? tick;
    // Rebuild the sorted list at most 4×/s rather than on every hit.
    void soon() => tick ??= Timer(const Duration(milliseconds: 250), () {
          tick = null;
          hosts = found.values.toList()..sort(_byIp);
          notifyListeners();
        });

    try {
      await VendorLookup.instance.load();
      final usePing = await pingAvailable();
      await runPool<int>(addresses, Platform.isAndroid ? 48 : 128, (addr) async {
        final ip = formatIpv4(addr);
        final r = usePing && !probePorts
            ? await _pingOnly(ip)
            : await probeHost(ip, usePing: usePing);
        if (r != null) found[ip] = RangeHost(ip, r.latencyMs, r.openPorts);
        scanned++;
        progress = 0.85 * scanned / total;
        soon();
      }, cancelled: () => _cancel);

      // Local hosts that ignored every probe still had to answer ARP.
      final arp = await readArpTable();
      if (!_cancel) {
        final wanted = {for (final a in addresses) formatIpv4(a)};
        for (final ip in arp.keys) {
          if (wanted.contains(ip)) found.putIfAbsent(ip, () => RangeHost(ip, null, {}));
        }
      }

      if (!_cancel && found.isNotEmpty) {
        progress = 0.9;
        notifyListeners();
        // MACs only exist for hosts on our own segment; routed ranges won't
        // have them. NetBIOS and reverse DNS work across subnets.
        final nb = await queryNetbios(found.keys);
        await runPool<RangeHost>(found.values.toList(), 32, (h) async {
          h.mac = arp[h.ip] ?? nb[h.ip]?.mac;
          h.vendor = VendorLookup.instance.vendorFor(h.mac);
          h.netbiosName = nb[h.ip]?.name;
          try {
            final r = await InternetAddress(h.ip).reverse().timeout(const Duration(seconds: 2));
            if (r.host != h.ip && !r.host.startsWith('_')) h.hostname = r.host;
          } catch (_) {}
        }, cancelled: () => _cancel);
      }
    } finally {
      tick?.cancel();
      hosts = found.values.toList()..sort(_byIp);
      cancelled = _cancel;
      elapsed = sw.elapsed;
      finishedAt = DateTime.now();
      scanning = false;
      progress = 1;
      notifyListeners();
    }
  }

  Future<ProbeResult?> _pingOnly(String ip) async {
    final r = await pingOnce(ip, timeout: const Duration(seconds: 1));
    return r.ok ? ProbeResult(latencyMs: r.timeMs) : null;
  }

  void _remember(String q) {
    recent
      ..remove(q)
      ..insert(0, q);
    if (recent.length > 12) recent = recent.sublist(0, 12);
    _prefs?.setStringList(_kRecentRanges, recent);
  }

  /// Results as CSV, for pasting into a spreadsheet or ticket.
  String toCsv() {
    String esc(String? v) {
      final s = v ?? '';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final rows = [
      'IP,Hostname,NetBIOS name,MAC,Vendor,Response ms,Open ports',
      for (final h in hosts)
        [
          h.ip,
          esc(h.hostname),
          esc(h.netbiosName),
          h.mac ?? '',
          esc(h.vendor),
          h.latencyMs?.toStringAsFixed(1) ?? '',
          esc((h.openPorts.toList()..sort()).join(' ')),
        ].join(','),
    ];
    return rows.join('\n');
  }

  static int _byIp(RangeHost a, RangeHost b) =>
      ipSortKey(a.ip).compareTo(ipSortKey(b.ip));
}
