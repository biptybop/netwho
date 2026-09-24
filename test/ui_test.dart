import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netwho/models/device.dart';
import 'package:netwho/state/device_store.dart';
import 'package:netwho/state/scan_controller.dart';
import 'package:netwho/state/settings_controller.dart';
import 'package:netwho/theme.dart';
import 'package:netwho/ui/device_detail_page.dart';
import 'package:netwho/ui/devices_page.dart';
import 'package:netwho/ui/tools_page.dart';

ScanController _scanner() {
  final s = ScanController(DeviceStore());
  s.devices = [
    Device(ip: '192.168.1.1', mac: '80:cc:9c:28:ab:96')
      ..isGateway = true
      ..online = true
      ..latencyMs = 3
      ..upnpName = 'MR60 (Gateway)'
      ..vendor = 'Netgear'
      ..openPorts = {80, 443, 53},
    Device(ip: '192.168.1.25', mac: 'b0:b3:69:ba:57:2f')
      ..online = true
      ..isNew = true
      ..mdnsName = 'Living Room TV'
      ..model = 'onn. Streaming Device 4K pro'
      ..services = {'_googlecast._tcp', '_airplay._tcp'}
      ..firstSeen = DateTime(2026, 9, 1)
      ..lastSeen = DateTime(2026, 9, 24),
    Device(ip: '192.168.1.40')
      ..lastSeen = DateTime(2026, 9, 20)
      ..customName = 'Grandma\'s tablet with a very long name that should ellipsize nicely'
      ..notes = 'Upstairs',
  ];
  return s;
}

Widget _app(Widget child, {Brightness b = Brightness.dark}) =>
    MaterialApp(theme: buildTheme(b), home: child);

void main() {
  for (final size in [const Size(390, 800), const Size(1200, 800)]) {
    testWidgets('devices page renders at ${size.width}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scanner = _scanner();
      await tester.pumpWidget(_app(DevicesPage(scanner: scanner, settings: SettingsController())));
      expect(find.text('MR60 (Gateway)'), findsOneWidget);
      expect(find.text('Living Room TV'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('Offline (1)'), findsOneWidget);
      await tester.ensureVisible(find.text('Offline (1)'));
      await tester.tap(find.text('Offline (1)'));
      await tester.pump();
      expect(find.text('Living Room TV'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('device detail renders and rename updates', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scanner = _scanner();
    final tv = scanner.devices[1];
    await tester.pumpWidget(_app(DeviceDetailPage(device: tv, scanner: scanner), b: Brightness.light));
    expect(find.text('Chromecast'), findsOneWidget);
    expect(find.text('b0:b3:69:ba:57:2f'), findsOneWidget);
    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Big TV');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tv.customName, 'Big TV');
    expect(find.text('Big TV'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tools page lists tools', (tester) async {
    final scanner = _scanner();
    await tester.pumpWidget(_app(ToolsPage(scanner: scanner, settings: SettingsController())));
    for (final t in ['Speed test', 'Ping', 'Traceroute', 'Port scan', 'DNS lookup', 'Wake on LAN']) {
      expect(find.text(t), findsOneWidget);
    }
    await tester.tap(find.text('Wake on LAN'));
    await tester.pumpAndSettle();
    expect(find.text('MAC address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
