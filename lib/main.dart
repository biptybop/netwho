import 'package:flutter/material.dart';

import 'state/device_store.dart';
import 'state/range_scan_controller.dart';
import 'state/scan_controller.dart';
import 'state/settings_controller.dart';
import 'theme.dart';
import 'ui/devices_page.dart';
import 'ui/tools_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsController();
  final store = DeviceStore();
  final ranges = RangeScanController();
  await Future.wait([settings.load(), store.load(), ranges.load()]);
  final scanner = ScanController(store);
  runApp(NetWhoApp(settings: settings, scanner: scanner, ranges: ranges));
  // Show what we remember; scanning waits until the user taps Scan.
  await scanner.loadCached();
}

class NetWhoApp extends StatelessWidget {
  const NetWhoApp({
    super.key,
    required this.settings,
    required this.scanner,
    required this.ranges,
  });

  final SettingsController settings;
  final ScanController scanner;
  final RangeScanController ranges;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'NetWho',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: settings.themeMode,
        home: HomeShell(settings: settings, scanner: scanner, ranges: ranges),
      ),
    );
  }
}

/// Hosts the two destinations, with a rail on wide windows and a bottom bar on
/// narrow ones.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.settings,
    required this.scanner,
    required this.ranges,
  });

  final SettingsController settings;
  final ScanController scanner;
  final RangeScanController ranges;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.devices_outlined, selected: Icons.devices, label: 'Devices'),
    (icon: Icons.handyman_outlined, selected: Icons.handyman, label: 'Tools'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      DevicesPage(scanner: widget.scanner, settings: widget.settings),
      ToolsPage(scanner: widget.scanner, settings: widget.settings, ranges: widget.ranges),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final content = IndexedStack(index: _index, children: pages);

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selected),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
