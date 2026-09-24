import 'package:flutter_test/flutter_test.dart';
import 'package:netwho/models/device.dart';
import 'package:netwho/models/device_type.dart';
import 'package:netwho/net/ipv4.dart';
import 'package:netwho/net/oui.dart';
import 'package:netwho/net/wol.dart';

void main() {
  group('ipv4', () {
    test('parse and format round-trip', () {
      expect(formatIpv4(parseIpv4('192.168.1.42')!), '192.168.1.42');
      expect(parseIpv4('300.1.1.1'), isNull);
      expect(parseIpv4('1.2.3'), isNull);
    });

    test('subnet hosts skip network and broadcast', () {
      final s = Subnet(parseIpv4('10.0.0.77')!, 24);
      expect(s.cidr, '10.0.0.0/24');
      expect(s.hosts.length, 254);
      expect(formatIpv4(s.hosts.first), '10.0.0.1');
      expect(formatIpv4(s.broadcast), '10.0.0.255');
    });

    test('mask to prefix', () {
      expect(prefixFromMask('255.255.255.0'), 24);
      expect(prefixFromMask('255.255.252.0'), 22);
    });
  });

  test('vendor names lose corporate suffixes', () {
    expect(cleanVendorName('Espressif Inc.'), 'Espressif');
    expect(cleanVendorName('Hui Zhou Gaoshengda Technology Co.,LTD'), 'Hui Zhou Gaoshengda Technology');
    expect(cleanVendorName('Google, Inc.'), 'Google');
    expect(cleanVendorName('Synology Incorporated'), 'Synology');
    expect(cleanVendorName('Intel Corporate'), 'Intel Corporate');
  });

  test('MAC helpers', () {
    expect(parseMac('AA-bb-cc-dd-ee-ff'), [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]);
    expect(parseMac('nope'), isNull);
    expect(isRandomizedMac('42:74:1e:15:d2:93'), isTrue);
    expect(isRandomizedMac('b0:2a:43:31:10:d2'), isFalse);
  });

  group('device', () {
    test('display name prefers what the user typed', () {
      final d = Device(ip: '192.168.1.5')
        ..hostname = 'desk-pc.lan'
        ..vendor = 'Intel';
      expect(d.displayName, 'desk-pc');
      d.customName = 'Office PC';
      expect(d.displayName, 'Office PC');
    });

    test('json round-trip keeps user fields', () {
      final d = Device(ip: '192.168.1.9', mac: 'aa:bb:cc:dd:ee:ff')
        ..customName = 'TV'
        ..typeOverride = DeviceType.tv
        ..services = {'_googlecast._tcp'}
        ..firstSeen = DateTime(2026, 1, 2);
      final back = Device.fromJson(d.toJson());
      expect(back.customName, 'TV');
      expect(back.typeOverride, DeviceType.tv);
      expect(back.services, contains('_googlecast._tcp'));
      expect(back.key, 'mac:aa:bb:cc:dd:ee:ff');
    });

    test('type guesses', () {
      expect(guessDeviceType(Device(ip: '1')..isGateway = true), DeviceType.router);
      expect(
          guessDeviceType(Device(ip: '1')
            ..services = {'_googlecast._tcp'}
            ..model = 'Google Home Mini'),
          DeviceType.speaker);
      expect(guessDeviceType(Device(ip: '1')..services = {'_googlecast._tcp'}), DeviceType.tv);
      expect(guessDeviceType(Device(ip: '1')..vendor = 'Synology Incorporated'), DeviceType.nas);
      expect(guessDeviceType(Device(ip: '1')..services = {'_ipp._tcp'}), DeviceType.printer);
      expect(guessDeviceType(Device(ip: '1')..openPorts = {62078}), DeviceType.phone);
      expect(guessDeviceType(Device(ip: '1')), DeviceType.unknown);
    });
  });
}
