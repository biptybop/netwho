import 'ipv4.dart';

/// An inclusive span of IPv4 addresses.
class IpRange {
  IpRange(this.start, this.end, this.source);

  final int start;
  final int end;

  /// The text the user typed for this range.
  final String source;

  int get size => end - start + 1;

  Iterable<int> get addresses sync* {
    for (var a = start; a <= end; a++) {
      yield a;
    }
  }

  @override
  String toString() => start == end
      ? formatIpv4(start)
      : '${formatIpv4(start)} – ${formatIpv4(end)}';
}

class RangeParseResult {
  RangeParseResult(this.ranges, this.errors);
  final List<IpRange> ranges;
  final List<String> errors;

  /// Distinct addresses across all ranges (overlaps counted once).
  List<int> get addresses {
    final seen = <int>{};
    for (final r in ranges) {
      seen.addAll(r.addresses);
    }
    return seen.toList()..sort();
  }

  int get totalSize => ranges.fold(0, (n, r) => n + r.size);
}

/// Parses ranges separated by commas, spaces or new lines. Accepts:
///
/// - `10.1.0.0/24`: CIDR (skips network and broadcast addresses)
/// - `10.1.0.10-10.1.0.50`: start–end
/// - `10.1.0.10-50`: start–end in the last octet
/// - `10.1.*.*` / `10.1.2.*`: wildcards
/// - `10.1.0.7`: a single address
RangeParseResult parseRanges(String text) {
  final ranges = <IpRange>[];
  final errors = <String>[];
  for (final raw in text.split(RegExp(r'[\s,;]+'))) {
    final token = raw.trim();
    if (token.isEmpty) continue;
    final r = _parseOne(token);
    if (r == null) {
      errors.add(token);
    } else {
      ranges.add(r);
    }
  }
  return RangeParseResult(ranges, errors);
}

IpRange? _parseOne(String t) {
  // CIDR
  final slash = t.indexOf('/');
  if (slash > 0) {
    final base = parseIpv4(t.substring(0, slash));
    final prefix = int.tryParse(t.substring(slash + 1));
    if (base == null || prefix == null || prefix < 8 || prefix > 32) return null;
    final s = Subnet(base, prefix);
    if (prefix >= 31) return IpRange(s.network, s.broadcast, t);
    return IpRange(s.network + 1, s.broadcast - 1, t);
  }

  // Wildcards: every * must come after the fixed octets.
  if (t.contains('*')) {
    final parts = t.split('.');
    if (parts.length != 4) return null;
    var start = 0, end = 0;
    var wild = false;
    for (final p in parts) {
      if (p == '*') {
        wild = true;
        start = start << 8;
        end = (end << 8) | 0xFF;
      } else {
        final n = int.tryParse(p);
        if (wild || n == null || n < 0 || n > 255) return null;
        start = (start << 8) | n;
        end = (end << 8) | n;
      }
    }
    // Skip .0 and .255 in the last octet, as a /24 sweep would.
    if (parts.last == '*') {
      start += 1;
      end -= 1;
    }
    return IpRange(start, end, t);
  }

  // Dash range, full or last-octet form.
  final dash = t.indexOf('-');
  if (dash > 0) {
    final start = parseIpv4(t.substring(0, dash));
    final rest = t.substring(dash + 1);
    if (start == null) return null;
    int? end = parseIpv4(rest);
    if (end == null) {
      final last = int.tryParse(rest);
      if (last == null || last < 0 || last > 255) return null;
      end = (start & 0xFFFFFF00) | last;
    }
    if (end < start) return null;
    return IpRange(start, end, t);
  }

  final single = parseIpv4(t);
  return single == null ? null : IpRange(single, single, t);
}
