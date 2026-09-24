import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/device.dart';
import '../net/local_network.dart';
import '../state/scan_controller.dart';
import '../state/settings_controller.dart';
import '../theme.dart';
import 'app_menu.dart';
import 'device_detail_page.dart';
import 'format.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.scanner, required this.settings});

  final ScanController scanner;
  final SettingsController settings;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  DeviceFilter _filter = DeviceFilter.all;
  String _query = '';
  bool _searching = false;

  ScanController get scanner => widget.scanner;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, _) {
        final list = scanner.filtered(_filter, _query);
        return Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search name, IP, MAC, vendor…',
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  )
                : const Text('NetWho'),
            actions: [
              IconButton(
                tooltip: _searching ? 'Close search' : 'Search',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _query = '';
                }),
              ),
              AppMenu(settings: widget.settings, scanner: scanner),
            ],
            bottom: scanner.scanning
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(4),
                    child: LinearProgressIndicator(value: scanner.progress),
                  )
                : null,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: scanner.scanning ? scanner.cancel : scanner.scan,
            icon: Icon(scanner.scanning ? Icons.stop : Icons.radar),
            label: Text(scanner.scanning ? 'Stop' : 'Scan'),
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: scanner.scan,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _NetworkCard(scanner: scanner)),
                  SliverToBoxAdapter(child: _filters(context)),
                  if (list.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(scanner: scanner, filtered: _filter != DeviceFilter.all || _query.isNotEmpty),
                    )
                  else
                    SliverList.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) => DeviceTile(
                        device: list[i],
                        onTap: () => _open(list[i]),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 88)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _filters(BuildContext context) {
    final all = scanner.devices.length;
    final offline = all - scanner.onlineCount;
    final options = [
      (DeviceFilter.all, 'All ($all)'),
      if (scanner.hasScanned || scanner.scanning) ...[
        (DeviceFilter.online, 'Online (${scanner.onlineCount})'),
        if (offline > 0 && !scanner.scanning) (DeviceFilter.offline, 'Offline ($offline)'),
      ],
      if (scanner.newCount > 0) (DeviceFilter.fresh, 'New (${scanner.newCount})'),
    ];
    if (!options.any((o) => o.$1 == _filter)) _filter = DeviceFilter.all;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          for (final (f, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  void _open(Device d) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DeviceDetailPage(device: d, scanner: scanner),
    ));
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({required this.scanner});

  final ScanController scanner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = scanner.network;
    final title = net?.wifiName ?? (net == null ? 'Network' : _ifaceLabel(net));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    net?.isWifi ?? true
                        ? Icons.wifi
                        : Icons.settings_ethernet,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (Platform.isAndroid && net != null && net.wifiName == null)
                    TextButton(
                      onPressed: () => _showWifiName(context),
                      child: const Text('Show Wi-Fi name'),
                    ),
                ],
              ),
              if (net != null) ...[
                const SizedBox(height: 8),
                Text(
                  'This device ${net.ip}  ·  Network ${net.subnet.cidr}'
                  '${net.gateway != null ? '  ·  Router ${net.gateway}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
                if (net.scanIsTruncated)
                  Text('Large network: scanning ${net.scanRange.cidr} only.',
                      style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _Stat(
                    label: 'Online',
                    value: scanner.hasScanned || scanner.scanning
                        ? '${scanner.onlineCount}'
                        : '—',
                  ),
                  if (scanner.newCount > 0)
                    _Stat(label: 'New', value: '${scanner.newCount}', highlight: true),
                  _Stat(label: 'Known', value: '${scanner.devices.length}'),
                  _Stat(
                    label: 'Last scan',
                    value: scanner.scanning ? 'now' : timeAgo(scanner.lastScan),
                  ),
                ],
              ),
              if (scanner.scanning) ...[
                const SizedBox(height: 8),
                Text(scanner.phase, style: theme.textTheme.bodySmall),
              ],
              if (scanner.error != null) ...[
                const SizedBox(height: 8),
                Text(scanner.error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _ifaceLabel(LocalNetwork net) {
    final kind = net.isWifi ? 'Wi-Fi' : 'Wired';
    // Windows adapter descriptions are long ("Intel(R) Wi-Fi 6E AX211 160MHz").
    return Platform.isWindows ? kind : '$kind (${net.interfaceName})';
  }

  Future<void> _showWifiName(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Android only shares the Wi-Fi name with apps allowed to use location.'),
      ));
      return;
    }
    final name = await readWifiName();
    if (name == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Couldn\'t read the Wi-Fi name. Is Location turned on?'),
      ));
      return;
    }
    scanner.setWifiName(name);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFeatures: tabularFigures,
              color: highlight ? theme.colorScheme.tertiary : null,
            )),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanner, required this.filtered});

  final ScanController scanner;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final text = scanner.scanning
        ? 'Looking for devices…'
        : filtered
            ? 'Nothing matches.'
            : 'No devices yet. Tap Scan to look for them.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

class DeviceTile extends StatelessWidget {
  const DeviceTile({super.key, required this.device, required this.onTap});

  final Device device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = device;
    final muted = !d.online;
    final details = <String>[
      d.ip,
      if (d.isSelf) 'This device',
      if (d.vendor != null && d.vendor != d.displayName) d.vendor!,
      if (d.vendor == null && d.model != null && d.model != d.displayName) d.model!,
    ];

    return ListTile(
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: muted
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primaryContainer,
            foregroundColor: muted
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onPrimaryContainer,
            child: Icon(d.type.icon),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: d.online ? onlineColor(context) : theme.colorScheme.outline,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              d.displayName,
              overflow: TextOverflow.ellipsis,
              style: muted ? TextStyle(color: theme.colorScheme.onSurfaceVariant) : null,
            ),
          ),
          if (d.isNew) ...[
            const SizedBox(width: 8),
            const _Badge('NEW'),
          ],
        ],
      ),
      subtitle: Text(details.join('  ·  '), overflow: TextOverflow.ellipsis),
      trailing: Text(
        d.online ? msText(d.latencyMs) : timeAgo(d.lastSeen),
        style: theme.textTheme.bodySmall?.copyWith(fontFeatures: tabularFigures),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onTertiaryContainer, fontWeight: FontWeight.bold)),
    );
  }
}
