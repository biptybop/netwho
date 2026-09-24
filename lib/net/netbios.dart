import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class NetbiosInfo {
  NetbiosInfo(this.name, this.mac);
  final String name;

  /// Windows and Samba report their MAC here, which is the only way to get
  /// one on Android where the ARP table is off limits.
  final String? mac;
}

/// Sends a NetBIOS node-status query to each of [ips] and waits [window]
/// for answers. Only Windows PCs, Samba servers and some NAS boxes reply.
Future<Map<String, NetbiosInfo>> queryNetbios(
  Iterable<String> ips, {
  Duration window = const Duration(milliseconds: 1500),
}) async {
  final found = <String, NetbiosInfo>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket!.receive();
      if (dg == null) return;
      final info = _parse(dg.data);
      if (info != null) found[dg.address.address] = info;
    });
    final packet = _query();
    for (final ip in ips) {
      try {
        socket.send(packet, InternetAddress(ip), 137);
      } catch (_) {}
    }
    await Future<void>.delayed(window);
    await sub.cancel();
  } catch (_) {
  } finally {
    socket?.close();
  }
  return found;
}

Uint8List _query() {
  final b = BytesBuilder();
  b.add([0x13, 0x37, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
  // Name "*" padded with NULs, first-level encoded: each nibble + 'A'.
  b.addByte(0x20);
  final raw = [0x2A, ...List.filled(15, 0)];
  for (final c in raw) {
    b.addByte(0x41 + (c >> 4));
    b.addByte(0x41 + (c & 0x0F));
  }
  b.addByte(0x00);
  b.add([0x00, 0x21, 0x00, 0x01]); // NBSTAT, IN
  return b.toBytes();
}

NetbiosInfo? _parse(Uint8List d) {
  try {
    var off = 12;
    // Skip the echoed name (labels, or a compression pointer).
    while (off < d.length) {
      final len = d[off];
      if (len == 0) {
        off += 1;
        break;
      }
      if (len & 0xC0 == 0xC0) {
        off += 2;
        break;
      }
      off += len + 1;
    }
    off += 10; // type, class, ttl, rdlength
    final count = d[off++];
    String? name;
    for (var i = 0; i < count; i++) {
      final entry = d.sublist(off, off + 18);
      off += 18;
      final suffix = entry[15];
      final group = entry[16] & 0x80 != 0;
      if (name == null && suffix == 0x00 && !group) {
        name = String.fromCharCodes(entry.sublist(0, 15)).trim();
      }
    }
    if (name == null || name.isEmpty) return null;
    String? mac;
    if (off + 6 <= d.length) {
      final bytes = d.sublist(off, off + 6);
      if (bytes.any((b) => b != 0)) {
        mac = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
      }
    }
    return NetbiosInfo(name, mac);
  } catch (_) {
    return null;
  }
}
