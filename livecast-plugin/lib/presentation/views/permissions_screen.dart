import 'package:flutter/material.dart';

/// Lists every Android permission THIS plugin's manifest requests, with a
/// plain-English reason for each. The list is short and honest — it must
/// match the merged manifest exactly (INTERNET only; see
/// `android/app/src/main/AndroidManifest.xml`). Read-only view.
///
/// The INTERNET permission here serves ONE purpose: the live transcript page
/// is served by this app to browsers on the user's own Wi-Fi (NanoHTTPD on a
/// LAN port). Nothing connects out to the app maker or any third party.
/// No license section here: the licenses view is a separate page (drawer /
/// About → Open-source licenses).
class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('App permissions')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Every permission the installed app requests, and why.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _sectionHeader('Permissions we request', theme),
          _item(
            context,
            Icons.public,
            'INTERNET',
            'One job: serve the live transcript page to browsers on YOUR '
                'Wi-Fi while a LiveCast session runs (the page is served by '
                'this device, on a local port — no data leaves your '
                'network). Nothing connects out to the app maker or to any '
                'third party; when no session is running, nothing is served '
                'at all.',
          ),
          const SizedBox(height: 24),
          _footer(context, theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style:
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String permId,
    String reason,
  ) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(
        permId,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
      subtitle: Text(reason, style: theme.textTheme.bodySmall),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
    );
  }

  Widget _footer(BuildContext context, ThemeData theme) {
    // Open-source note + source link as PLAIN TEXT only — never a tappable
    // link (repo rule: no URL launching anywhere in the ecosystem).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This app is fully open source — every line it runs is public '
            'and auditable.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'github.com/octoflashdev/kenosis-web',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
