import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../models/device_type.dart';
import '../net/ipv4.dart';
import '../net/oui.dart';
import '../net/ports.dart';
import '../net/wol.dart';
import '../state/scan_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'tool_views.dart';

class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({super.key, required this.device, required this.scanner});

  final Device device;
  final ScanController scanner;

  /// The live object for this device; a scan replaces the list's objects.
  Device get _d => scanner.resolve(device);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, _) {
        final d = _d;
        final theme = Theme.of(context);
        final webPort = d.openPorts.where(isWebPort).toList()..sort();

        return Scaffold(
          appBar: AppBar(
            title: Text(d.displayName, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(context),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Header(
                  device: d,
                  checked: scanner.hasScanned,
                  onTypeTap: () => _pickType(context),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.category_outlined, size: 18),
                      label: const Text('Change type'),
                      onPressed: () => _pickType(context),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.notes, size: 18),
                      label: Text(d.notes == null ? 'Add note' : 'Edit note'),
                      onPressed: () => _editNotes(context),
                    ),
                    if (webPort.isNotEmpty)
                      ActionChip(
                        avatar: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open web page'),
                        onPressed: () => openWeb(d.ip, webPort.first),
                      ),
                    if (d.mac != null && !d.isSelf)
                      ActionChip(
                        avatar: const Icon(Icons.power_settings_new, size: 18),
                        label: const Text('Wake up'),
                        onPressed: () => _wake(context),
                      ),
                  ],
                ),
                if (d.notes != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(d.notes!),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _Section(
                  title: 'Details',
                  child: Column(children: _detailRows(context, d)),
                ),
                if (d.services.isNotEmpty)
                  _Section(
                    title: 'Advertised services',
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in d.services.toList()..sort())
                          Chip(label: Text(_serviceLabel(s)), visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ),
                _Section(
                  title: 'Ping',
                  initiallyExpanded: false,
                  keepAlive: false,
                  child: PingView(host: d.ip),
                ),
                _Section(
                  title: 'Open ports',
                  initiallyExpanded: false,
                  child: PortScanView(
                    host: d.ip,
                    onFinished: (open) => scanner.updateDevice(d, (d) => d.openPorts = open.toSet()),
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: () => _forget(context),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Forget this device'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _detailRows(BuildContext context, Device d) {
    final rows = <(String, String?)>[
      ('Status', d.online
          ? 'Online'
          : '${scanner.hasScanned ? 'Offline' : 'Not checked yet'} · last seen ${timeAgo(d.lastSeen)}'),
      ('IP address', d.ip),
      ('MAC address', d.mac == null
          ? null
          : isRandomizedMac(d.mac) ? '${d.mac}  (private / randomized)' : d.mac),
      ('Vendor', d.vendor),
      ('Model', d.model),
      ('Hostname', d.hostname),
      ('Bonjour name', d.mdnsName),
      ('Windows name', d.netbiosName),
      ('UPnP name', d.upnpName),
      ('Response time', d.online ? msText(d.latencyMs) : null),
      ('First seen', d.firstSeen == null ? null : dateText(d.firstSeen!.toLocal())),
      ('Last seen', d.lastSeen == null ? null : dateText(d.lastSeen!.toLocal())),
    ];
    return [
      for (final (label, value) in rows)
        if (value != null) _InfoRow(label: label, value: value),
    ];
  }

  Future<void> _rename(BuildContext context) async {
    final ctrl = TextEditingController(text: _d.customName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this device'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: _d.displayName),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          if (_d.customName != null)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Use detected name'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final name = result.trim();
    await scanner.updateDevice(_d, (d) => d.customName = name.isEmpty ? null : name);
  }

  Future<void> _pickType(BuildContext context) async {
    final guessed = guessDeviceType(_d);
    final picked = await showDialog<DeviceType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Device type'),
        children: [
          SizedBox(
            width: 360,
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (final t in DeviceType.values)
                  SizedBox(
                    width: 110,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, t),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          children: [
                            Icon(t.icon,
                                color: t == _d.type
                                    ? Theme.of(context).colorScheme.primary
                                    : null),
                            const SizedBox(height: 4),
                            Text(
                              t == guessed ? '${t.label}\n(auto)' : t.label,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await scanner.updateDevice(_d, (d) => d.typeOverride = picked == guessed ? null : picked);
  }

  Future<void> _editNotes(BuildContext context) async {
    final ctrl = TextEditingController(text: _d.notes ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'e.g. Grandma\'s tablet, upstairs'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final text = result.trim();
    await scanner.updateDevice(_d, (d) => d.notes = text.isEmpty ? null : text);
  }

  Future<void> _wake(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final net = scanner.network;
    final ok = await sendWakeOnLan(
      _d.mac!,
      subnetBroadcast: net == null ? null : formatIpv4(net.subnet.broadcast),
    );
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Wake-up signal sent. It only works if Wake-on-LAN is enabled on that _d.'
          : 'That MAC address doesn\'t look valid.'),
    ));
  }

  Future<void> _forget(BuildContext context) async {
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this device?'),
        content: const Text(
          'Its name, type and note will be removed. If it is still on the '
          'network it will show up again as new on the next scan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await scanner.forget(_d);
    nav.pop();
  }
}

String _serviceLabel(String s) {
  const names = {
    '_googlecast._tcp': 'Chromecast',
    '_airplay._tcp': 'AirPlay',
    '_raop._tcp': 'AirPlay audio',
    '_ipp._tcp': 'Printing',
    '_ipps._tcp': 'Printing',
    '_printer._tcp': 'Printing',
    '_pdl-datastream._tcp': 'Printing',
    '_scanner._tcp': 'Scanning',
    '_uscan._tcp': 'Scanning',
    '_smb._tcp': 'File sharing',
    '_afpovertcp._tcp': 'Apple file sharing',
    '_adisk._tcp': 'Time Machine',
    '_ssh._tcp': 'SSH',
    '_sftp-ssh._tcp': 'SFTP',
    '_http._tcp': 'Web page',
    '_hap._tcp': 'HomeKit',
    '_matter._tcp': 'Matter',
    '_matterc._udp': 'Matter setup',
    '_spotify-connect._tcp': 'Spotify Connect',
    '_sonos._tcp': 'Sonos',
    '_companion-link._tcp': 'Apple device',
    '_device-info._tcp': 'Device info',
    '_workstation._tcp': 'Workstation',
    '_amzn-wplay._tcp': 'Fire TV',
    '_androidtvremote2._tcp': 'Android TV',
    '_home-assistant._tcp': 'Home Assistant',
    '_esphomelib._tcp': 'ESPHome',
    '_hue._tcp': 'Philips Hue',
    '_rfb._tcp': 'Screen sharing',
    '_plexmediasvr._tcp': 'Plex',
    '_nvstream._tcp': 'Game streaming',
    '_sleep-proxy._udp': 'Sleep proxy',
  };
  return names[s] ?? s.replaceAll('._tcp', '').replaceAll('._udp', '').replaceFirst('_', '');
}

class _Header extends StatelessWidget {
  const _Header({required this.device, required this.checked, required this.onTypeTap});

  final Device device;
  final bool checked;
  final VoidCallback onTypeTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = device;
    final tags = [
      if (d.isGateway) 'Router',
      if (d.isSelf) 'This device',
      if (d.isNew) 'New',
    ];
    return Row(
      children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: onTypeTap,
          child: CircleAvatar(
            radius: 32,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Icon(d.type.icon, size: 32),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.displayName, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.circle,
                      size: 10,
                      color: d.online ? onlineColor(context) : theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      [d.type.label, d.online ? 'Online' : checked ? 'Offline' : 'Not checked yet', ...tags].join('  ·  '),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.initiallyExpanded = true,
    this.keepAlive = true,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  /// False for sections that do work while built (ping), so collapsing
  /// them stops it.
  final bool keepAlive;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      shape: const Border(),
      collapsedShape: const Border(),
      maintainState: keepAlive,
      children: [child],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onLongPress: () => _copy(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
  }
}
