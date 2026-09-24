import 'dart:async';
import 'dart:io';

import 'ping.dart';

/// Ports tried during a sweep. Many devices ignore ping but will either
/// accept or actively refuse one of these, which proves they are there.
const sweepPorts = [80, 443, 22, 445, 139, 53, 8080, 62078, 554, 8008, 5000];

class ProbeResult {
  ProbeResult({this.latencyMs, Set<int>? openPorts})
      : openPorts = openPorts ?? {};

  double? latencyMs;
  final Set<int> openPorts;
}

const _econnrefused = {111, 61, 10061}; // Linux/Android, macOS, Windows

/// Checks whether [ip] is up. Returns null when nothing answered.
Future<ProbeResult?> probeHost(
  String ip, {
  bool usePing = true,
  Duration timeout = const Duration(milliseconds: 900),
}) async {
  final result = ProbeResult();
  var alive = false;

  Future<void> tcp(int port) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(ip, port, timeout: timeout);
      s.destroy();
      alive = true;
      result.openPorts.add(port);
      result.latencyMs ??= sw.elapsedMicroseconds / 1000;
    } on SocketException catch (e) {
      if (_econnrefused.contains(e.osError?.errorCode)) {
        alive = true;
        result.latencyMs ??= sw.elapsedMicroseconds / 1000;
      }
    } catch (_) {}
  }

  Future<void> icmp() async {
    final r = await pingOnce(ip, timeout: const Duration(seconds: 1));
    if (r.ok) {
      alive = true;
      result.latencyMs = r.timeMs; // ICMP time is the better number
    }
  }

  await Future.wait([
    if (usePing) icmp(),
    for (final p in sweepPorts) tcp(p),
  ]);
  return alive ? result : null;
}

/// Runs [task] over [items] with at most [concurrency] in flight.
Future<void> runPool<T>(
  Iterable<T> items,
  int concurrency,
  Future<void> Function(T item) task, {
  bool Function()? cancelled,
}) async {
  final it = items.iterator;
  Future<void> worker() async {
    while (true) {
      if (cancelled?.call() ?? false) return;
      if (!it.moveNext()) return;
      await task(it.current);
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
}
