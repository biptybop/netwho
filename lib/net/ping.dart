import 'dart:io';

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

/// True if the system ping binary is usable at all.
Future<bool> pingAvailable() async {
  try {
    final r = await Process.run('ping', ['-c', '1', '-W', '1', '-n', '127.0.0.1']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
