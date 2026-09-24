import 'package:flutter_test/flutter_test.dart';
import 'package:netwho/net/ip_range.dart';
import 'package:netwho/net/ipv4.dart';

List<String> _ips(String q) => parseRanges(q).addresses.map(formatIpv4).toList();

void main() {
  test('CIDR skips network and broadcast', () {
    final ips = _ips('10.1.0.0/24');
    expect(ips.length, 254);
    expect(ips.first, '10.1.0.1');
    expect(ips.last, '10.1.0.254');
    expect(_ips('10.1.0.8/31'), ['10.1.0.8', '10.1.0.9']);
    expect(_ips('10.1.0.8/32'), ['10.1.0.8']);
  });

  test('dash ranges, full and last-octet', () {
    expect(_ips('192.168.5.10-192.168.5.12'), ['192.168.5.10', '192.168.5.11', '192.168.5.12']);
    expect(parseRanges('192.168.5.250-2').errors, ['192.168.5.250-2']); // end < start
    expect(_ips('192.168.5.10-12'), ['192.168.5.10', '192.168.5.11', '192.168.5.12']);
    expect(_ips('10.0.0.254-10.0.1.1'), ['10.0.0.254', '10.0.0.255', '10.0.1.0', '10.0.1.1']);
  });

  test('wildcards', () {
    final ips = _ips('172.16.4.*');
    expect(ips.length, 254);
    expect(ips.first, '172.16.4.1');
    expect(parseRanges('172.16.*.*').totalSize, 65534);
    expect(parseRanges('172.*.4.1').errors, ['172.*.4.1']);
  });

  test('several ranges, overlaps counted once, bad tokens reported', () {
    final r = parseRanges('10.0.0.1-5, 10.0.0.4-6\n10.9.9.9; nonsense 300.1.1.1');
    expect(r.addresses.map(formatIpv4), [
      '10.0.0.1', '10.0.0.2', '10.0.0.3', '10.0.0.4', '10.0.0.5', '10.0.0.6', '10.9.9.9',
    ]);
    expect(r.errors, ['nonsense', '300.1.1.1']);
  });

  test('reversed and oversized prefixes are rejected', () {
    expect(parseRanges('10.0.0.9-10.0.0.1').errors, isNotEmpty);
    expect(parseRanges('10.0.0.0/4').errors, isNotEmpty);
  });
}
