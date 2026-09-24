import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../net/ping.dart';
import '../net/ports.dart';
import '../theme.dart';
import 'format.dart';

/// Pings a host once a second and shows each reply plus a running summary.
class PingView extends StatefulWidget {
  const PingView({super.key, required this.host, this.count = 10});

  final String host;
  final int count;

  @override
  State<PingView> createState() => _PingViewState();
}

class _PingViewState extends State<PingView> {
  final _replies = <PingReply>[];
  bool _running = false;
  bool _stop = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _stop = true;
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _replies.clear();
      _running = true;
      _stop = false;
    });
    for (var i = 0; i < widget.count && !_stop; i++) {
      final started = DateTime.now();
      final r = await pingOnce(widget.host, timeout: const Duration(seconds: 2));
      if (!mounted || _stop) return;
      setState(() => _replies.add(r));
      final wait = const Duration(seconds: 1) - DateTime.now().difference(started);
      if (!wait.isNegative) await Future<void>.delayed(wait);
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = _replies.where((r) => r.ok).map((r) => r.timeMs!).toList();
    final loss = _replies.isEmpty ? 0 : 100 * (_replies.length - ok.length) ~/ _replies.length;
    final avg = ok.isEmpty ? null : ok.reduce((a, b) => a + b) / ok.length;
    final min = ok.isEmpty ? null : ok.reduce((a, b) => a < b ? a : b);
    final max = ok.isEmpty ? null : ok.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _stat(context, 'Sent', '${_replies.length}'),
            _stat(context, 'Loss', '$loss%'),
            _stat(context, 'Min', msText(min)),
            _stat(context, 'Avg', msText(avg)),
            _stat(context, 'Max', msText(max)),
          ],
        ),
        const SizedBox(height: 12),
        for (final (i, r) in _replies.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 32, child: Text('${i + 1}', style: theme.textTheme.bodySmall)),
                Icon(r.ok ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: r.ok ? onlineColor(context) : theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(r.ok ? msText(r.timeMs) : 'No reply',
                    style: const TextStyle(fontFeatures: tabularFigures)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: _running
              ? OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _stop = true;
                    _running = false;
                  }),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                )
              : FilledButton.tonalIcon(
                  onPressed: _run,
                  icon: const Icon(Icons.replay),
                  label: const Text('Ping again'),
                ),
        ),
      ],
    );
  }
}

Widget _stat(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: theme.textTheme.titleMedium?.copyWith(fontFeatures: tabularFigures)),
      Text(label, style: theme.textTheme.labelSmall),
    ],
  );
}

enum PortRange {
  common('Common ports', null),
  low('Ports 1–1024', 1024),
  all('All ports (slow)', 65535);

  const PortRange(this.label, this.upTo);
  final String label;
  final int? upTo;

  Iterable<int> get ports => upTo == null
      ? commonPorts.keys
      : {for (var p = 1; p <= upTo!; p++) p, ...commonPorts.keys};
}

/// Port scanner with a range picker and a live list of open ports.
class PortScanView extends StatefulWidget {
  const PortScanView({super.key, required this.host, this.onFinished});

  final String host;
  final void Function(List<int> open)? onFinished;

  @override
  State<PortScanView> createState() => _PortScanViewState();
}

class _PortScanViewState extends State<PortScanView> {
  PortRange _range = PortRange.common;
  final _open = <int>[];
  double? _progress;
  bool _stop = false;
  bool _ran = false;

  @override
  void dispose() {
    _stop = true;
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _open.clear();
      _progress = 0;
      _stop = false;
      _ran = true;
    });
    var lastUpdate = DateTime.now();
    final open = await scanPorts(
      widget.host,
      _range.ports,
      concurrency: _range == PortRange.all ? 256 : 96,
      cancelled: () => _stop,
      onOpen: (p) {
        if (mounted) setState(() => _open..add(p)..sort());
      },
      onProgress: (f) {
        final now = DateTime.now();
        if (mounted && now.difference(lastUpdate).inMilliseconds > 100) {
          lastUpdate = now;
          setState(() => _progress = f);
        }
      },
    );
    if (!mounted) return;
    setState(() => _progress = null);
    if (!_stop) widget.onFinished?.call(open);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanning = _progress != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<PortRange>(
              value: _range,
              onChanged: scanning ? null : (r) => setState(() => _range = r!),
              items: [
                for (final r in PortRange.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
            ),
            if (scanning)
              OutlinedButton.icon(
                onPressed: () => setState(() => _stop = true),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              )
            else
              FilledButton.tonalIcon(
                onPressed: _scan,
                icon: const Icon(Icons.search),
                label: Text(_ran ? 'Scan again' : 'Scan ports'),
              ),
          ],
        ),
        if (scanning) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _progress),
        ],
        if (_ran) ...[
          const SizedBox(height: 8),
          if (_open.isEmpty && !scanning)
            Text('No open ports found.', style: theme.textTheme.bodyMedium)
          else
            for (final p in _open) PortTile(host: widget.host, port: p),
        ],
      ],
    );
  }
}

class PortTile extends StatelessWidget {
  const PortTile({super.key, required this.host, required this.port});

  final String host;
  final int port;

  @override
  Widget build(BuildContext context) {
    final web = isWebPort(port);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 56,
        child: Text('$port',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontFeatures: tabularFigures)),
      ),
      title: Text(portName(port)),
      trailing: web
          ? IconButton(
              tooltip: 'Open in browser',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => openWeb(host, port),
            )
          : null,
    );
  }
}

Future<void> openWeb(String host, int port) async {
  final scheme = isTlsPort(port) ? 'https' : 'http';
  final showPort = !(port == 80 && scheme == 'http') && !(port == 443 && scheme == 'https');
  await launchUrl(
    Uri.parse('$scheme://$host${showPort ? ':$port' : ''}/'),
    mode: LaunchMode.externalApplication,
  );
}
