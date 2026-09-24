import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What a host described about itself over UPnP / SSDP.
class UpnpInfo {
  String? friendlyName;
  String? manufacturer;
  String? model;
  String? deviceType;
  String? server;
  String? location;
}

/// Sends an SSDP M-SEARCH, collects responses for [window], then fetches each
/// device's description XML for its name and model.
///
/// With no [targets] it multicasts. Multicast replies are often lost (Wi-Fi
/// multicast filtering, host firewalls), so the scanner follows up with a
/// unicast search to every live host, which gets through far more reliably.
Future<Map<String, UpnpInfo>> discoverUpnp({
  Iterable<String> targets = const [],
  Duration window = const Duration(seconds: 3),
}) async {
  final found = <String, UpnpInfo>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    String msg(String host, String st) => 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $host:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: $st\r\n\r\n';
    final done = Completer<void>();
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket!.receive();
      if (dg == null) return;
      final text = utf8.decode(dg.data, allowMalformed: true);
      final info = found.putIfAbsent(dg.address.address, UpnpInfo.new);
      for (final line in text.split('\r\n')) {
        final c = line.indexOf(':');
        if (c <= 0) continue;
        final key = line.substring(0, c).trim().toLowerCase();
        final value = line.substring(c + 1).trim();
        if (key == 'location' && info.location == null) info.location = value;
        if (key == 'server') info.server ??= value;
      }
    });
    if (targets.isEmpty) {
      final group = InternetAddress('239.255.255.250');
      for (var i = 0; i < 2; i++) {
        socket.send(utf8.encode(msg(group.address, 'ssdp:all')), group, 1900);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } else {
      for (final ip in targets) {
        try {
          socket.send(utf8.encode(msg(ip, 'upnp:rootdevice')), InternetAddress(ip), 1900);
        } catch (_) {}
      }
    }
    Timer(window, () => done.complete());
    await done.future;
    await sub.cancel();
  } catch (_) {
  } finally {
    socket?.close();
  }

  await Future.wait(found.values
      .where((i) => i.location != null)
      .map((i) => _fetchDescription(i)));
  return found;
}

Future<void> _fetchDescription(UpnpInfo info) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final req = await client.getUrl(Uri.parse(info.location!));
    final res = await req.close().timeout(const Duration(seconds: 3));
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 3));
    String? tag(String name) {
      final m = RegExp('<$name>([^<]*)</$name>', caseSensitive: false).firstMatch(body);
      final v = m?.group(1)?.trim();
      return (v == null || v.isEmpty) ? null : _unescape(v);
    }

    info.friendlyName = tag('friendlyName');
    info.manufacturer = tag('manufacturer');
    info.model = tag('modelName') ?? tag('modelDescription');
    info.deviceType = tag('deviceType');
  } catch (_) {
  } finally {
    client.close(force: true);
  }
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");
