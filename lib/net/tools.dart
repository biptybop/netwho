import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ping.dart';

class Hop {
  Hop(this.ttl, this.address, this.timeMs, {this.name});
  final int ttl;
  final String? address;
  final double? timeMs;
  String? name;
}

/// Traceroute built on `ping -t <ttl>`, so it needs no extra binaries or root.
Stream<Hop> traceroute(String host, {int maxHops = 30}) async* {
  final target = await _resolve(host);
  for (var ttl = 1; ttl <= maxHops; ttl++) {
    final sw = Stopwatch()..start();
    final r = await pingOnce(target, ttl: ttl, timeout: const Duration(seconds: 2));
    final elapsed = sw.elapsedMicroseconds / 1000;
    if (r.ttlExceeded) {
      yield await _named(Hop(ttl, r.from, elapsed));
    } else if (r.ok) {
      yield await _named(Hop(ttl, r.from ?? target, r.timeMs));
      return;
    } else {
      yield Hop(ttl, null, null);
    }
  }
}

Future<Hop> _named(Hop hop) async {
  if (hop.address == null) return hop;
  try {
    final r = await InternetAddress(hop.address!).reverse().timeout(const Duration(seconds: 2));
    if (r.host != hop.address && !r.host.startsWith('_')) hop.name = r.host;
  } catch (_) {}
  return hop;
}

Future<String> _resolve(String host) async {
  if (InternetAddress.tryParse(host) != null) return host;
  final list = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
  return list.first.address;
}

class DnsResult {
  DnsResult(this.addresses, this.reverseName, this.elapsedMs);
  final List<String> addresses;
  final String? reverseName;
  final int elapsedMs;
}

/// Forward lookup for names, reverse lookup for addresses.
Future<DnsResult> dnsLookup(String query) async {
  final sw = Stopwatch()..start();
  final ip = InternetAddress.tryParse(query.trim());
  if (ip != null) {
    final r = await ip.reverse().timeout(const Duration(seconds: 5));
    return DnsResult([ip.address], r.host == ip.address ? null : r.host, sw.elapsedMilliseconds);
  }
  final list = await InternetAddress.lookup(query.trim()).timeout(const Duration(seconds: 5));
  return DnsResult([for (final a in list) a.address], null, sw.elapsedMilliseconds);
}

class PublicInfo {
  PublicInfo({this.ip, this.isp, this.city, this.country});
  final String? ip;
  final String? isp;
  final String? city;
  final String? country;
}

/// Public IP and ISP, via Cloudflare's trace endpoint and ipinfo.io. Only
/// called when the user taps the button.
Future<PublicInfo> fetchPublicInfo() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    Future<String> get(String url) async {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 8));
      return res.transform(utf8.decoder).join();
    }

    String? ip;
    try {
      final trace = await get('https://1.1.1.1/cdn-cgi/trace');
      ip = RegExp(r'^ip=(.+)$', multiLine: true).firstMatch(trace)?.group(1);
    } catch (_) {}
    try {
      final j = jsonDecode(await get('https://ipinfo.io/json')) as Map<String, dynamic>;
      return PublicInfo(
        ip: ip ?? j['ip'] as String?,
        isp: (j['org'] as String?)?.replaceFirst(RegExp(r'^AS\d+\s+'), ''),
        city: j['city'] as String?,
        country: j['country'] as String?,
      );
    } catch (_) {
      return PublicInfo(ip: ip);
    }
  } finally {
    client.close(force: true);
  }
}

class SpeedSample {
  SpeedSample(this.phase, this.mbps, {this.latencyMs, this.done = false});
  final String phase; // 'latency', 'download', 'upload'
  final double? mbps;
  final double? latencyMs;
  final bool done;
}

/// Simple speed test against Cloudflare's public speed endpoints: latency,
/// then ~8 s of download, then ~8 s of upload.
Stream<SpeedSample> speedTest({bool Function()? cancelled}) async* {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..maxConnectionsPerHost = 6;
  const base = 'https://speed.cloudflare.com';
  try {
    // Latency: median of a few tiny requests.
    final times = <double>[];
    for (var i = 0; i < 6; i++) {
      final sw = Stopwatch()..start();
      final req = await client.getUrl(Uri.parse('$base/__down?bytes=0'));
      final res = await req.close();
      await res.drain<void>();
      if (i > 0) times.add(sw.elapsedMicroseconds / 1000); // skip TLS setup
    }
    times.sort();
    final latency = times[times.length ~/ 2];
    yield SpeedSample('latency', null, latencyMs: latency);

    // Download: parallel streams for a fixed time.
    var bytes = 0;
    final sw = Stopwatch()..start();
    const duration = Duration(seconds: 8);
    var stop = false;
    Future<void> downWorker() async {
      while (!stop) {
        try {
          final req = await client.getUrl(Uri.parse('$base/__down?bytes=25000000'));
          final res = await req.close();
          await for (final chunk in res) {
            bytes += chunk.length;
            if (stop) break;
          }
        } catch (_) {
          if (!stop) await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }

    final workers = [for (var i = 0; i < 4; i++) downWorker()];
    while (sw.elapsed < duration && !(cancelled?.call() ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      yield SpeedSample('download', bytes * 8 / sw.elapsedMicroseconds);
    }
    stop = true;
    final down = bytes * 8 / sw.elapsedMicroseconds;
    yield SpeedSample('download', down, done: true);
    client.close(force: true);
    await Future.wait(workers).timeout(const Duration(seconds: 2), onTimeout: () => []);
    if (cancelled?.call() ?? false) return;

    // Upload.
    final upClient = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    var sent = 0;
    stop = false;
    final chunk = Uint8List(64 * 1024);
    final usw = Stopwatch()..start();
    Future<void> upWorker() async {
      while (!stop) {
        try {
          final req = await upClient.postUrl(Uri.parse('$base/__up'));
          req.headers.contentType = ContentType.binary;
          req.contentLength = 8 * 1024 * 1024;
          for (var i = 0; i < 128 && !stop; i++) {
            req.add(chunk);
            await req.flush();
            sent += chunk.length;
          }
          if (stop) {
            req.abort();
            return;
          }
          await (await req.close()).drain<void>();
        } catch (_) {
          if (!stop) await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }

    final upWorkers = [for (var i = 0; i < 3; i++) upWorker()];
    while (usw.elapsed < duration && !(cancelled?.call() ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      yield SpeedSample('upload', sent * 8 / usw.elapsedMicroseconds);
    }
    stop = true;
    yield SpeedSample('upload', sent * 8 / usw.elapsedMicroseconds, done: true);
    upClient.close(force: true);
    await Future.wait(upWorkers).timeout(const Duration(seconds: 2), onTimeout: () => []);
  } finally {
    client.close(force: true);
  }
}
