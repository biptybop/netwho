import 'package:flutter/material.dart';

import '../state/scan_controller.dart';
import '../state/settings_controller.dart';

/// The ⋮ menu shared by both tabs: housekeeping, appearance and about.
class AppMenu extends StatelessWidget {
  const AppMenu({super.key, required this.settings, required this.scanner});

  final SettingsController settings;
  final ScanController scanner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = settings.themeMode;

    Widget item(IconData icon, String text) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(text),
        );

    return PopupMenuButton<VoidCallback>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: scanner.acknowledgeNew,
          enabled: scanner.newCount > 0,
          child: item(Icons.done_all, 'Mark all as seen'),
        ),
        PopupMenuItem(
          value: () => _confirmForgetAll(context),
          child: item(Icons.delete_sweep_outlined, 'Forget remembered devices…'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          child: Text('Appearance', style: theme.textTheme.labelMedium),
        ),
        for (final mode in ThemeMode.values)
          PopupMenuItem(
            value: () => settings.setThemeMode(mode),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(mode.icon),
              title: Text(mode.label),
              trailing: mode == current
                  ? Icon(Icons.check, color: theme.colorScheme.primary)
                  : null,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => _about(context),
          child: item(Icons.info_outline, 'About'),
        ),
      ],
    );
  }

  Future<void> _confirmForgetAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget remembered devices?'),
        content: const Text(
          'This clears the names, types and notes you set for devices on this '
          'network, and removes offline devices from the list. It can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
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
    if (ok == true) await scanner.forgetAll();
  }

  void _about(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'NetWho',
      applicationVersion: '1.1.0',
      applicationIcon: Image.asset('assets/icon/icon.png', width: 48, height: 48),
      children: const [
        Text(
          'See who is on your network. No ads, no accounts, no tracking — '
          'scan results stay on this device.\n\n'
          'The public IP lookup and speed test contact Cloudflare and '
          'ipinfo.io, and only when you tap them.\n\n'
          'MAC vendor names come from the Wireshark manufacturer database.',
        ),
      ],
    );
  }
}
