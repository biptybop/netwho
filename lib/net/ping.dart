import 'dart:io';

import 'windows/iphlpapi.dart' as win;

/// Result of one ICMP echo via the system `ping` binary, which works without
/// root on both desktop Linux and Android.
class PingReply {
  const PingReply({this.timeMs, this.from, this.ttlExceeded = false});

  /// Round-trip time, or null when nothing answered.
  final double? timeMs;

  /// Who replied. For a TTL-exceeded reply this is the router along the path.
  final String? from;
  final bool ttlExceeded;

  bool get ok => timeMs != null;
}

final _time = RegExp(r'time[=<]\s*([\d.]+)\s*ms');
final _fromBytes = RegExp(r'bytes from ([^\s:(]+)');
final _fromExceeded = RegExp(r'[Ff]rom ([^\s:(]+).*(?:Time to live exceeded|TTL exceeded)');
final _fromExceededParen = RegExp(r'[Ff]rom [^\s]+ \(([\d.]+)\).*(?:Time to live exceeded|TTL exceeded)');

Future<PingReply> pingOnce(
  String host, {
  Duration timeout = const Duration(seconds: 1),
  int? ttl,
}) async {
  if (Platform.isWindows) return _pingWindows(host, timeout, ttl);
  final secs = (timeout.inMilliseconds / 1000).ceil().clamp(1, 30);
  final args = ['-c', '1', '-W', '$secs', '-n'];
  if (ttl != null) args.addAll(['-t', '$ttl']);
  args.add(host);
  try {
    final r = await Process.run('ping', args)
        .timeout(timeout + const Duration(seconds: 2));
    final out = '${r.stdout}\n${r.stderr}';
    final exceeded = _fromExceededParen.firstMatch(out) ?? _fromExceeded.firstMatch(out);
    if (exceeded != null) {
      return PingReply(from: exceeded.group(1), ttlExceeded: true);
    }
    final t = _time.firstMatch(out);
    if (t != null) {
      return PingReply(
        timeMs: double.tryParse(t.group(1)!),
        from: _fromBytes.firstMatch(out)?.group(1),
      );
    }
  } catch (_) {}
  return const PingReply();
}

/// Windows: ICMP through iphlpapi (see windows/iphlpapi.dart). Takes an IPv4
/// address; names are resolved first.
Future<PingReply> _pingWindows(String host, Duration timeout, int? ttl) async {
  try {
    var ip = host;
    if (InternetAddress.tryParse(host) == null) {
      final list = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
      ip = list.first.address;
    }
    final r = await win.icmpEcho(ip, timeoutMs: timeout.inMilliseconds, ttl: ttl);
    if (r == null) return const PingReply();
    if (win.isTtlExceeded(r)) return PingReply(from: r.$2, ttlExceeded: true);
    if (win.isEchoSuccess(r, ip)) {
      return PingReply(timeMs: r.$3.toDouble(), from: r.$2);
    }
  } catch (_) {}
  return const PingReply();
}

/// True if the system ping binary is usable at all.
Future<bool> pingAvailable() async {
  if (Platform.isWindows) return true;
  try {
    final r = await Process.run('ping', ['-c', '1', '-W', '1', '-n', '127.0.0.1']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
