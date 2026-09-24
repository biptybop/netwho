import 'dart:io';
import 'dart:typed_data';

/// Parses "aa:bb:cc:dd:ee:ff", "aa-bb-…" or "aabbcc…" into 6 bytes.
Uint8List? parseMac(String text) {
  final hex = text.replaceAll(RegExp('[^0-9a-fA-F]'), '');
  if (hex.length != 12) return null;
  return Uint8List.fromList([
    for (var i = 0; i < 12; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// Sends a Wake-on-LAN magic packet to the global broadcast address and,
/// if given, the subnet broadcast. Returns false if the MAC is invalid.
Future<bool> sendWakeOnLan(String macText, {String? subnetBroadcast}) async {
  final mac = parseMac(macText);
  if (mac == null) return false;
  final packet = BytesBuilder()..add(List.filled(6, 0xFF));
  for (var i = 0; i < 16; i++) {
    packet.add(mac);
  }
  final bytes = packet.toBytes();
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  try {
    socket.broadcastEnabled = true;
    for (final target in {'255.255.255.255', ?subnetBroadcast}) {
      for (final port in [9, 7]) {
        socket.send(bytes, InternetAddress(target), port);
      }
    }
  } finally {
    socket.close();
  }
  return true;
}
