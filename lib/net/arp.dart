import 'dart:io';

/// IP → MAC pairs from the kernel neighbour table.
///
/// Works on desktop Linux. Android 10+ blocks apps from reading it, so there
/// this returns an empty map and MACs come from NetBIOS where possible.
Future<Map<String, String>> readArpTable() async {
  final table = <String, String>{};
  try {
    final lines = await File('/proc/net/arp').readAsLines();
    for (final line in lines.skip(1)) {
      final cols = line.split(RegExp(r'\s+'));
      if (cols.length < 4) continue;
      final flags = int.tryParse(cols[2].replaceFirst('0x', ''), radix: 16) ?? 0;
      final mac = cols[3].toLowerCase();
      if (flags & 0x2 == 0 || mac == '00:00:00:00:00:00') continue;
      table[cols[0]] = mac;
    }
  } catch (_) {}
  if (table.isNotEmpty) return table;

  try {
    final r = await Process.run('ip', ['-4', 'neigh', 'show']);
    if (r.exitCode == 0) {
      final re = RegExp(r'^(\S+) .*lladdr ([0-9a-f:]{17}) (\S+)');
      for (final line in (r.stdout as String).split('\n')) {
        final m = re.firstMatch(line);
        if (m == null || m.group(3) == 'FAILED' || m.group(3) == 'INCOMPLETE') continue;
        table[m.group(1)!] = m.group(2)!;
      }
    }
  } catch (_) {}
  return table;
}
