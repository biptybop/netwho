import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import 'ipv4.dart';
import 'windows/iphlpapi.dart' as win;

/// The network this device is on, as far as we can tell.
class LocalNetwork {
  LocalNetwork({
    required this.interfaceName,
    required this.ip,
    required this.prefix,
    this.gateway,
    this.mac,
    this.wifiName,
    this.isWifi = true,
  });

  /// Interface name on Linux/Android, adapter description on Windows.
  final String interfaceName;
  final bool isWifi;
  final String ip;
  final int prefix;
  final String? gateway;
  final String? mac;
  String? wifiName;

  Subnet get subnet => Subnet(parseIpv4(ip)!, prefix);

  /// Largest range we sweep. Anything bigger (a /16 office network, say) is
  /// narrowed to the /22 around our own address to keep scans quick.
  static const minScanPrefix = 22;

  Subnet get scanRange =>
      prefix >= minScanPrefix ? subnet : Subnet(parseIpv4(ip)!, minScanPrefix);

  bool get scanIsTruncated => prefix < minScanPrefix;

  /// Stable-ish identity for remembering devices per network.
  String get key => '${subnet.cidr}@${gateway ?? '-'}';
}

class NoNetworkException implements Exception {
  @override
  String toString() =>
      'No local network found. Connect to Wi-Fi or Ethernet and try again.';
}

Future<LocalNetwork> detectLocalNetwork() async {
  LocalNetwork? net;
  if (Platform.isLinux) net = await _detectLinux();
  if (Platform.isWindows) net = _detectWindows();
  if (net == null && Platform.isAndroid) net = await _detectAndroid();
  net ??= await _detectFallback();
  if (net == null) throw NoNetworkException();
  net.wifiName ??= await readWifiName();
  return net;
}

/// Wi-Fi network name. On Android this needs location permission, so it
/// quietly returns null until the user grants it.
Future<String?> readWifiName() async {
  try {
    final name = await NetworkInfo().getWifiName();
    if (name == null || name.isEmpty || name == '<unknown ssid>') return null;
    return name.replaceAll('"', '');
  } catch (_) {
    return null;
  }
}

Future<LocalNetwork?> _detectLinux() async {
  try {
    final route = await Process.run('ip', ['-j', '-4', 'route', 'show', 'default']);
    final addr = await Process.run('ip', ['-j', '-4', 'addr', 'show']);
    if (route.exitCode != 0 || addr.exitCode != 0) return null;

    final routes = (jsonDecode(route.stdout as String) as List)
        .cast<Map<String, dynamic>>()
      ..sort((a, b) =>
          ((a['metric'] as int?) ?? 0).compareTo((b['metric'] as int?) ?? 0));
    final ifaces = (jsonDecode(addr.stdout as String) as List)
        .cast<Map<String, dynamic>>();

    // Prefer the interface carrying the default route; otherwise the first
    // private-range address that isn't loopback or a VPN point-to-point link.
    String? gateway;
    String? dev;
    if (routes.isNotEmpty) {
      gateway = routes.first['gateway'] as String?;
      dev = routes.first['dev'] as String?;
    }

    for (final iface in ifaces) {
      final name = iface['ifname'] as String;
      if (dev != null && name != dev) continue;
      for (final a in (iface['addr_info'] as List).cast<Map<String, dynamic>>()) {
        final ip = a['local'] as String;
        final prefix = a['prefixlen'] as int;
        if (ip.startsWith('127.') || prefix >= 31) continue;
        String? mac;
        try {
          mac = File('/sys/class/net/$name/address').readAsStringSync().trim();
        } catch (_) {}
        return LocalNetwork(
          interfaceName: name,
          ip: ip,
          prefix: prefix,
          gateway: gateway,
          mac: mac,
          isWifi: Directory('/sys/class/net/$name/wireless').existsSync(),
        );
      }
    }
  } catch (_) {}
  return null;
}

/// Prefers the adapter with a default gateway, like the Linux path; that
/// skips Hyper-V/WSL/VPN virtual adapters, which normally have none.
LocalNetwork? _detectWindows() {
  try {
    final adapters = win.windowsAdapters();
    final pick = adapters.where((a) => a.gateway != null && _isPrivate(a.ip)).firstOrNull ??
        adapters.where((a) => a.gateway != null).firstOrNull ??
        adapters.where((a) => _isPrivate(a.ip)).firstOrNull;
    if (pick == null) return null;
    var prefix = prefixFromMask(pick.mask);
    if (prefix < 8 || prefix > 30) prefix = 24;
    return LocalNetwork(
      interfaceName: pick.description,
      ip: pick.ip,
      prefix: prefix,
      gateway: pick.gateway,
      mac: pick.mac,
      isWifi: pick.isWifi,
    );
  } catch (_) {
    return null;
  }
}

Future<LocalNetwork?> _detectAndroid() async {
  try {
    final info = NetworkInfo();
    final ip = await info.getWifiIP();
    if (ip == null || parseIpv4(ip) == null) return null;
    final mask = await info.getWifiSubmask();
    final gateway = await info.getWifiGatewayIP();
    var prefix = mask == null ? 24 : prefixFromMask(mask);
    if (prefix < 8 || prefix > 30) prefix = 24;
    return LocalNetwork(
      interfaceName: 'wlan0',
      ip: ip,
      prefix: prefix,
      gateway: (gateway == null || gateway == '0.0.0.0') ? null : gateway,
    );
  } catch (_) {
    return null;
  }
}

/// Last resort: first private IPv4 address, assumed to be a /24.
Future<LocalNetwork?> _detectFallback() async {
  final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  for (final iface in ifaces) {
    for (final a in iface.addresses) {
      final ip = a.address;
      if (_isPrivate(ip)) {
        return LocalNetwork(
          interfaceName: iface.name,
          ip: ip,
          prefix: 24,
          isWifi: iface.name.startsWith('w'),
        );
      }
    }
  }
  return null;
}

bool _isPrivate(String ip) {
  final v = parseIpv4(ip);
  if (v == null) return false;
  return Subnet(parseIpv4('10.0.0.0')!, 8).contains(v) ||
      Subnet(parseIpv4('172.16.0.0')!, 12).contains(v) ||
      Subnet(parseIpv4('192.168.0.0')!, 16).contains(v);
}
