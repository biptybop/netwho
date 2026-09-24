@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:netwho/net/arp.dart';
import 'package:netwho/net/local_network.dart';
import 'package:netwho/net/mdns.dart';
import 'package:netwho/net/ping.dart';
import 'package:netwho/net/prober.dart';
import 'package:netwho/net/windows/iphlpapi.dart';

/// Runs only on Windows (the CI build machine): calls the real iphlpapi
/// functions. Touches only this machine, never the network around it.
void main() {
  test('adapters are listed with a usable IPv4 address', () {
    final adapters = windowsAdapters();
    for (final a in adapters) {
      // ignore: avoid_print
      print('adapter ${a.description} ${a.ip}/${a.mask} gw ${a.gateway} mac ${a.mac} wifi ${a.isWifi}');
    }
    expect(adapters, isNotEmpty);
    expect(adapters.every((a) => a.ip.split('.').length == 4), isTrue);
  });

  test('local network is detected', () async {
    final net = await detectLocalNetwork();
    // ignore: avoid_print
    print('network ${net.interfaceName} ${net.ip}/${net.prefix} gw ${net.gateway}');
    expect(net.prefix, inInclusiveRange(8, 30));
  });

  test('ARP table reads without error', () async {
    final arp = await readArpTable();
    // ignore: avoid_print
    print('arp entries: ${arp.length}');
    expect(arp.values.every((m) => RegExp(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$').hasMatch(m)), isTrue);
  });

  test('ICMP ping to loopback succeeds, and to this machine', () async {
    final r = await pingOnce('127.0.0.1');
    expect(r.ok, isTrue, reason: 'loopback ping failed');
    final net = await detectLocalNetwork();
    final self = await pingOnce(net.ip);
    expect(self.ok, isTrue, reason: 'ping to own address failed');
    expect(await pingAvailable(), isTrue);
  });

  test('probe finds this machine alive', () async {
    final net = await detectLocalNetwork();
    expect(await probeHost(net.ip), isNotNull);
  });

  test('mDNS client starts (port 5353 or fallback)', () async {
    final m = MdnsBrowser();
    expect(await m.start(), isTrue);
    m.stop();
  });
}
