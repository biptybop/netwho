import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../net/ip_range.dart';
import '../net/ports.dart';
import '../state/range_scan_controller.dart';
import '../state/scan_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'tool_views.dart';

/// Largest scan we allow in one go (a /16).
const _maxAddresses = 65536;

/// Above this we ask before starting, since it can take a while.
const _confirmAbove = 4096;

class RangeScanPage extends StatefulWidget {
  const RangeScanPage({super.key, required this.ranges, required this.scanner});

  final RangeScanController ranges;
  final ScanController scanner;

  @override
  State<RangeScanPage> createState() => _RangeScanPageState();
}

class _RangeScanPageState extends State<RangeScanPage> {
  late final _ctrl = TextEditingController(
    text: widget.ranges.lastQuery ?? widget.scanner.network?.subnet.cidr ?? '',
  );
  String _filter = '';

  RangeScanController get rs => widget.ranges;

  Future<void> _start() async {
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final parsed = parseRanges(_ctrl.text);
    if (parsed.errors.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text('Didn\'t understand: ${parsed.errors.join(', ')}'),
      ));
      return;
    }
    if (parsed.ranges.isEmpty) return;
    final addrs = parsed.addresses;
    if (addrs.length > _maxAddresses) {
      messenger.showSnackBar(SnackBar(
        content: Text('That\'s ${addrs.length} addresses. The limit is '
            '$_maxAddresses (a /16) per scan; split it into smaller ranges.'),
      ));
      return;
    }
    if (addrs.length > _confirmAbove) {
      final perSec = Platform.isAndroid ? 40 : 110;
      final mins = (addrs.length / perSec / 60).ceil();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Large scan'),
          content: Text('${addrs.length} addresses could take up to about '
              '$mins min. You can leave this page while it runs, or stop it '
              'at any time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Scan')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await rs.scan(_ctrl.text, addrs);
  }

  String get _fileName {
    final t = rs.finishedAt ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'netwho-range-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}.csv';
  }

  /// Desktop: a normal save dialog. Android: the share sheet (Files, Drive,
  /// email…), since Android apps can't simply write to a folder you pick.
  Future<void> _saveCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    final csv = rs.toCsv();
    try {
      if (Platform.isAndroid) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$_fileName');
        await file.writeAsString(csv);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'NetWho range scan',
        ));
        return;
      }
      final loc = await getSaveLocation(
        suggestedName: _fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv'], mimeTypes: ['text/csv']),
        ],
      );
      if (loc == null) return; // cancelled
      var path = loc.path;
      if (!path.toLowerCase().endsWith('.csv')) path = '$path.csv';
      await File(path).writeAsString(csv);
      messenger.showSnackBar(SnackBar(content: Text('Saved ${rs.hosts.length} rows to $path')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Couldn\'t save the file: $e')));
    }
  }

  void _copyCsv() {
    Clipboard.setData(ClipboardData(text: rs.toCsv()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Copied ${rs.hosts.length} rows as CSV. Paste into a spreadsheet or ticket.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: rs,
      builder: (context, _) {
        final theme = Theme.of(context);
        final preview = parseRanges(_ctrl.text);
        final q = _filter.trim().toLowerCase();
        final shown = q.isEmpty
            ? rs.hosts
            : rs.hosts
                .where((h) => [h.ip, h.hostname, h.netbiosName, h.mac, h.vendor]
                    .whereType<String>()
                    .any((s) => s.toLowerCase().contains(q)))
                .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Range scan'),
            actions: [
              if (rs.hosts.isNotEmpty && !rs.scanning)
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Export results',
                  onSelected: (action) => action(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _saveCsv,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Platform.isAndroid ? Icons.share_outlined : Icons.save_alt),
                        title: Text(Platform.isAndroid ? 'Share CSV file…' : 'Save CSV file…'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _copyCsv,
                      child: const ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.copy_all_outlined),
                        title: Text('Copy to clipboard'),
                      ),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download_outlined),
                        SizedBox(width: 6),
                        Text('Export'),
                        Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
            ],
            bottom: rs.scanning
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(4),
                    child: LinearProgressIndicator(value: rs.progress),
                  )
                : null,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                TextField(
                  controller: _ctrl,
                  enabled: !rs.scanning,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Ranges',
                    hintText: '10.1.0.0/24, 10.2.5.1-120, 172.16.*.*',
                    helperText: 'CIDR, start-end, wildcards or single IPs. '
                        'Separate several with commas or new lines.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  preview.errors.isNotEmpty
                      ? 'Not understood: ${preview.errors.join(', ')}'
                      : preview.ranges.isEmpty
                          ? ''
                          : '${preview.totalSize} addresses: '
                              '${preview.ranges.map((r) => r.toString()).join(';  ')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: preview.errors.isNotEmpty ? theme.colorScheme.error : null,
                  ),
                ),
                if (rs.recent.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Recent', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final r in rs.recent)
                        InputChip(
                          label: Text(r.replaceAll('\n', ', '), overflow: TextOverflow.ellipsis),
                          onPressed: rs.scanning
                              ? null
                              : () => setState(() => _ctrl.text = r),
                          onDeleted: () => rs.forgetRecent(r),
                          deleteButtonTooltipMessage: 'Remove from recent',
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Also check common ports'),
                  subtitle: const Text('Finds devices that ignore ping. Slower.'),
                  value: rs.probePorts,
                  onChanged: rs.scanning ? null : rs.setProbePorts,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (rs.scanning)
                      OutlinedButton.icon(
                        onPressed: rs.cancel,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: preview.ranges.isEmpty || preview.errors.isNotEmpty
                            ? null
                            : _start,
                        icon: const Icon(Icons.radar),
                        label: const Text('Scan ranges'),
                      ),
                    const SizedBox(width: 16),
                    Expanded(child: Text(_status(), style: theme.textTheme.bodySmall)),
                  ],
                ),
                if (rs.hosts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  if (rs.hosts.length > 8)
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Filter results',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  const SizedBox(height: 8),
                  for (final h in shown)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.circle, size: 12, color: onlineColor(context)),
                      minLeadingWidth: 12,
                      title: Text(h.name.isEmpty ? h.ip : '${h.ip}  ·  ${h.name}',
                          overflow: TextOverflow.ellipsis),
                      subtitle: _subtitle(h) == null ? null : Text(_subtitle(h)!,
                          overflow: TextOverflow.ellipsis),
                      trailing: Text(msText(h.latencyMs),
                          style: theme.textTheme.bodySmall?.copyWith(fontFeatures: tabularFigures)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => RangeHostPage(host: h),
                      )),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String? _subtitle(RangeHost h) {
    final parts = [
      if (h.vendor != null) h.vendor!,
      if (h.mac != null && h.vendor == null) h.mac!,
      if (h.openPorts.isNotEmpty)
        'ports ${(h.openPorts.toList()..sort()).join(', ')}',
    ];
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  String _status() {
    if (rs.scanning) {
      return '${rs.scanned} of ${rs.total} checked · ${rs.hosts.length} responding';
    }
    if (rs.finishedAt == null) return '';
    final secs = (rs.elapsed?.inMilliseconds ?? 0) / 1000;
    return '${rs.cancelled ? 'Stopped' : 'Done'}: ${rs.hosts.length} responding '
        'of ${rs.total} in ${secs.toStringAsFixed(1)} s';
  }
}

/// Details and quick tools for one address found by a range scan.
class RangeHostPage extends StatelessWidget {
  const RangeHostPage({super.key, required this.host});

  final RangeHost host;

  @override
  Widget build(BuildContext context) {
    final h = host;
    final theme = Theme.of(context);
    final rows = <(String, String?)>[
      ('IP address', h.ip),
      ('Hostname', h.hostname),
      ('Windows name', h.netbiosName),
      ('MAC address', h.mac),
      ('Vendor', h.vendor),
      ('Response time', msText(h.latencyMs)),
      if (h.openPorts.isNotEmpty)
        ('Seen open', (h.openPorts.toList()..sort()).map((p) => '$p ${portName(p)}').join('\n')),
    ];
    final web = (h.openPorts.where(isWebPort).toList()..sort());
    return Scaffold(
      appBar: AppBar(title: Text(h.name.isEmpty ? h.ip : h.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final (label, value) in rows)
              if (value != null)
                Padding(
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
                      Expanded(child: SelectableText(value)),
                    ],
                  ),
                ),
            if (web.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => openWeb(h.ip, web.first),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open web page'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text('Ping', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            PingView(host: h.ip, count: 5),
            const SizedBox(height: 24),
            Text('Ports', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            PortScanView(host: h.ip),
          ],
        ),
      ),
    );
  }
}
