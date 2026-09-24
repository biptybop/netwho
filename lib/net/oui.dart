import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// MAC address → manufacturer, from the bundled Wireshark OUI table
/// (rebuild with tool/build_oui.py).
class VendorLookup {
  VendorLookup._();
  static final instance = VendorLookup._();

  Map<String, String>? _table;
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final data = await rootBundle.load('assets/data/oui.tsv.gz');
      final text = utf8.decode(
        gzip.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)),
      );
      final table = <String, String>{};
      for (final line in text.split('\n')) {
        final tab = line.indexOf('\t');
        if (tab > 0) table[line.substring(0, tab)] = line.substring(tab + 1);
      }
      _table = table;
    } catch (_) {
      _table = const {};
    }
  }

  /// Needs [load] to have finished; returns null for unknown prefixes.
  String? vendorFor(String? mac) {
    if (mac == null || _table == null) return null;
    final hex = mac.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
    if (hex.length != 12) return null;
    if (isRandomizedMac(mac)) return null;
    final name = _table![hex.substring(0, 9)] ??
        _table![hex.substring(0, 7)] ??
        _table![hex.substring(0, 6)];
    return name == null ? null : cleanVendorName(name);
  }
}

/// Phones and newer laptops use a random "private" MAC per Wi-Fi network;
/// those have the locally-administered bit set and no real vendor.
bool isRandomizedMac(String? mac) {
  if (mac == null || mac.length < 2) return false;
  final first = int.tryParse(mac.substring(0, 2), radix: 16);
  return first != null && first & 0x02 != 0;
}

final _corpSuffix = RegExp(
  r'[\s,.]+(inc|incorporated|ltd|limited|llc|co|corp|corporation|gmbh|ag|s\.?a|'
  r'b\.?v|plc|pty|oy|ab|srl|s\.?p\.?a|kg|l\.?p)\.?$',
  caseSensitive: false,
);

/// "Espressif Inc." → "Espressif", "Hui Zhou Gaoshengda Technology Co.,LTD"
/// → "Hui Zhou Gaoshengda Technology".
String cleanVendorName(String name) {
  var n = name.trim();
  for (var i = 0; i < 3; i++) {
    final stripped = n.replaceFirst(_corpSuffix, '');
    if (stripped == n || stripped.isEmpty) break;
    n = stripped;
  }
  return n.replaceFirst(RegExp(r'[\s,]+$'), '');
}
