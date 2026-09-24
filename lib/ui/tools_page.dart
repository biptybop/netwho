import 'dart:async';

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../net/ipv4.dart';
import '../net/tools.dart';
import '../net/wol.dart';
import '../state/range_scan_controller.dart';
import '../state/scan_controller.dart';
import '../state/settings_controller.dart';
import '../theme.dart';
import 'app_menu.dart';
import 'format.dart';
import 'range_scan_page.dart';
import 'tool_views.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({
    super.key,
    required this.scanner,
    required this.settings,
    required this.ranges,
  });

  final ScanController scanner;
  final SettingsController settings;
  final RangeScanController ranges;

  @override
  Widget build(BuildContext context) {
    final tools = [
      (Icons.travel_explore, 'Range scan', 'Scan other subnets or custom IP ranges',
          () => RangeScanPage(ranges: ranges, scanner: scanner)),
      (Icons.public, 'My internet connection', 'Public IP address and provider',
          () => _NetworkInfoTool(scanner: scanner)),
      (Icons.speed, 'Speed test', 'Download, upload and latency',
          () => const _SpeedTestTool()),
      (Icons.network_ping, 'Ping', 'Is it reachable, and how fast?',
          () => _HostTool(title: 'Ping', scanner: scanner, builder: (h) => PingView(key: ValueKey(h), host: h))),
      (Icons.alt_route, 'Traceroute', 'The path your traffic takes',
          () => _HostTool(title: 'Traceroute', scanner: scanner, initial: 'one.one.one.one',
              builder: (h) => _TracerouteView(key: ValueKey(h), host: h))),
      (Icons.lan_outlined, 'Port scan', 'Which services a device offers',
          () => _HostTool(title: 'Port scan', scanner: scanner,
              builder: (h) => PortScanView(key: ValueKey(h), host: h))),
      (Icons.dns_outlined, 'DNS lookup', 'Name to address, or address to name',
          () => _HostTool(title: 'DNS lookup', scanner: scanner, initial: 'example.com',
              builder: (h) => _DnsView(key: ValueKey(h), query: h))),
      (Icons.power_settings_new, 'Wake on LAN', 'Turn on a sleeping computer',
          () => _WakeTool(scanner: scanner)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
        actions: [AppMenu(settings: settings, scanner: scanner)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final (icon, title, subtitle, page) in tools)
              ListTile(
                leading: Icon(icon),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => page(),
                )),
              ),
          ],
        ),
      ),
    );
  }
}

/// Page with a host field (typed or picked from known devices) and a result
/// area built for the chosen host.
class _HostTool extends StatefulWidget {
  const _HostTool({
    required this.title,
    required this.scanner,
    required this.builder,
    this.initial,
  });

  final String title;
  final ScanController scanner;
  final Widget Function(String host) builder;
  final String? initial;

  @override
  State<_HostTool> createState() => _HostToolState();
}

class _HostToolState extends State<_HostTool> {
  late final _ctrl = TextEditingController(
      text: widget.initial ?? widget.scanner.network?.gateway ?? '');
  String? _host;

  void _go() {
    final h = _ctrl.text.trim();
    if (h.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _host = h);
  }

  Future<void> _pick() async {
    final d = await pickDevice(context, widget.scanner.devices);
    if (d == null) return;
    _ctrl.text = d.ip;
    _go();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      labelText: 'Address or name',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Pick a device',
                        icon: const Icon(Icons.devices_outlined),
                        onPressed: _pick,
                      ),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onSubmitted: (_) => _go(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _go, child: const Text('Go')),
              ],
            ),
            const SizedBox(height: 16),
            if (_host != null) widget.builder(_host!),
          ],
        ),
      ),
    );
  }
}

Future<Device?> pickDevice(BuildContext context, List<Device> devices) {
  return showModalBottomSheet<Device>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: devices.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No devices yet — run a scan first.'),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                for (final d in devices)
                  ListTile(
                    leading: Icon(d.type.icon),
                    title: Text(d.displayName),
                    subtitle: Text(d.ip),
                    onTap: () => Navigator.pop(context, d),
                  ),
              ],
            ),
    ),
  );
}

class _TracerouteView extends StatefulWidget {
  const _TracerouteView({super.key, required this.host});
  final String host;

  @override
  State<_TracerouteView> createState() => _TracerouteViewState();
}

class _TracerouteViewState extends State<_TracerouteView> {
  final _hops = <Hop>[];
  StreamSubscription<Hop>? _sub;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = traceroute(widget.host).listen(
      (h) => setState(() => _hops.add(h)),
      onError: (Object e) => setState(() {
        _error = 'Couldn\'t trace ${widget.host}: $e';
        _done = true;
      }),
      onDone: () => setState(() => _done = true),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in _hops)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(width: 28, child: Text('${h.ttl}', style: theme.textTheme.titleSmall)),
            title: Text(h.address == null ? '* no reply' : (h.name ?? h.address!)),
            subtitle: h.name != null ? Text(h.address!) : null,
            trailing: Text(msText(h.timeMs),
                style: const TextStyle(fontFeatures: tabularFigures)),
          ),
        if (!_done) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
        if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ],
    );
  }
}

class _DnsView extends StatelessWidget {
  const _DnsView({super.key, required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<DnsResult>(
      future: dnsLookup(query),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Lookup failed: ${snap.error}',
              style: TextStyle(color: theme.colorScheme.error));
        }
        if (!snap.hasData) return const LinearProgressIndicator();
        final r = snap.data!;
        final isIp = parseIpv4(query) != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isIp)
              _row(context, 'Name', r.reverseName ?? 'No name registered')
            else
              for (final a in r.addresses) _row(context, a.contains(':') ? 'IPv6' : 'IPv4', a),
            _row(context, 'Took', '${r.elapsedMs} ms'),
          ],
        );
      },
    );
  }
}

Widget _row(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _NetworkInfoTool extends StatefulWidget {
  const _NetworkInfoTool({required this.scanner});
  final ScanController scanner;

  @override
  State<_NetworkInfoTool> createState() => _NetworkInfoToolState();
}

class _NetworkInfoToolState extends State<_NetworkInfoTool> {
  Future<PublicInfo>? _public;

  @override
  Widget build(BuildContext context) {
    final net = widget.scanner.network;
    return Scaffold(
      appBar: AppBar(title: const Text('My internet connection')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('On this network', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (net == null)
              const Text('Not connected.')
            else ...[
              if (net.wifiName != null) _row(context, 'Wi-Fi', net.wifiName!),
              _row(context, 'Interface', net.interfaceName),
              _row(context, 'Your address', net.ip),
              _row(context, 'Network', net.subnet.cidr),
              _row(context, 'Router', net.gateway ?? 'unknown'),
              if (net.mac != null) _row(context, 'Your MAC', net.mac!),
            ],
            const SizedBox(height: 24),
            Text('On the internet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_public == null)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => setState(() => _public = fetchPublicInfo()),
                  icon: const Icon(Icons.public),
                  label: const Text('Look up my public IP'),
                ),
              )
            else
              FutureBuilder<PublicInfo>(
                future: _public,
                builder: (context, snap) {
                  if (snap.hasError) return Text('Lookup failed: ${snap.error}');
                  if (!snap.hasData) return const LinearProgressIndicator();
                  final p = snap.data!;
                  return Column(
                    children: [
                      _row(context, 'Public IP', p.ip ?? 'unknown'),
                      if (p.isp != null) _row(context, 'Provider', p.isp!),
                      if (p.city != null || p.country != null)
                        _row(context, 'Location',
                            [p.city, p.country].whereType<String>().join(', ')),
                    ],
                  );
                },
              ),
            const SizedBox(height: 8),
            Text(
              'Uses Cloudflare and ipinfo.io, only when you tap the button.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedTestTool extends StatefulWidget {
  const _SpeedTestTool();

  @override
  State<_SpeedTestTool> createState() => _SpeedTestToolState();
}

class _SpeedTestToolState extends State<_SpeedTestTool> {
  StreamSubscription<SpeedSample>? _sub;
  double? _latency, _down, _up;
  String? _phase;
  String? _error;
  bool _cancel = false;

  void _start() {
    setState(() {
      _latency = _down = _up = null;
      _error = null;
      _phase = 'latency';
      _cancel = false;
    });
    _sub = speedTest(cancelled: () => _cancel).listen(
      (s) => setState(() {
        _phase = s.done && s.phase == 'upload' ? null : s.phase;
        if (s.latencyMs != null) _latency = s.latencyMs;
        if (s.phase == 'download' && s.mbps != null) _down = s.mbps;
        if (s.phase == 'upload' && s.mbps != null) _up = s.mbps;
      }),
      onError: (Object e) => setState(() {
        _error = 'Speed test failed: $e';
        _phase = null;
      }),
      onDone: () => setState(() => _phase = null),
    );
  }

  @override
  void dispose() {
    _cancel = true;
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = _phase != null;
    Widget big(String label, String value, bool active) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFeatures: tabularFigures,
                    color: active ? theme.colorScheme.primary : null,
                  )),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        );
    String mbps(double? v) => v == null ? '—' : v < 10 ? v.toStringAsFixed(1) : '${v.round()}';

    return Scaffold(
      appBar: AppBar(title: const Text('Speed test')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                big('Latency (ms)', _latency == null ? '—' : '${_latency!.round()}', _phase == 'latency'),
                big('Download (Mbps)', mbps(_down), _phase == 'download'),
                big('Upload (Mbps)', mbps(_up), _phase == 'upload'),
              ],
            ),
            const SizedBox(height: 24),
            if (running) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Center(
              child: running
                  ? OutlinedButton.icon(
                      onPressed: () => setState(() => _cancel = true),
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    )
                  : FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.speed),
                      label: Text(_down == null ? 'Start' : 'Run again'),
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            Text(
              'Measures against Cloudflare\'s speed test servers and uses roughly '
              '100–500 MB of data on a fast connection — mind your mobile data.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _WakeTool extends StatefulWidget {
  const _WakeTool({required this.scanner});
  final ScanController scanner;

  @override
  State<_WakeTool> createState() => _WakeToolState();
}

class _WakeToolState extends State<_WakeTool> {
  final _ctrl = TextEditingController();

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final net = widget.scanner.network;
    final ok = await sendWakeOnLan(
      _ctrl.text,
      subnetBroadcast: net == null ? null : formatIpv4(net.subnet.broadcast),
    );
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Wake-up signal sent.' : 'Enter a MAC like aa:bb:cc:dd:ee:ff.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final withMac = widget.scanner.devices.where((d) => d.mac != null && !d.isSelf).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Wake on LAN')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      labelText: 'MAC address',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Pick a device',
                        icon: const Icon(Icons.devices_outlined),
                        onPressed: () async {
                          final d = await pickDevice(context, withMac);
                          if (d != null) setState(() => _ctrl.text = d.mac!);
                        },
                      ),
                    ),
                    autocorrect: false,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _send, child: const Text('Wake')),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'The computer must have Wake-on-LAN turned on in its settings and '
              'be plugged in by cable on most models.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
