import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const KenosisPluginApp());

/// One human sentence per known failure signature the service logs.
///
/// The fetch log's `status` field is "ok" or `error:<message>` where the
/// message is whatever the failing step threw/recorded (see
/// `InternetPluginService.kt` — every `logFetchError` call site). Those raw
/// strings are honest but terse; this maps each known signature to what a
/// user can act on. Unknown messages pass through verbatim — the log never
/// hides the raw reason, it only translates known cases.
String describeFetchError(String status) {
  final msg = status.startsWith('error:') ? status.substring(6) : status;
  if (msg.startsWith('no-usable-result')) {
    return "Google's top pick opens in a site's own app instead of a web "
        'page, and no openable link could be read from the results page.';
  }
  if (msg.startsWith('no-results')) {
    return 'The search engine answered, but no result links could be read '
        'from its results page.';
  }
  if (msg.startsWith('all-results-app-gated')) {
    return 'Every result opens in its own app (Facebook, Instagram, TikTok '
        'or X) — none of them can be read in the in-app browser.';
  }
  if (msg.contains('bot protection')) {
    return 'The search engine blocked this device as a possible bot. Try a '
        'different search engine.';
  }
  if (msg.contains('WebView JS extraction returned null')) {
    return 'The page rendered, but its text could not be extracted from it.';
  }
  if (msg.contains('timeout')) {
    return 'The page took too long to load — the fetch was abandoned.';
  }
  if (msg.startsWith('HTTP 4')) {
    return 'The site refused the request ($msg).';
  }
  if (msg.startsWith('HTTP 5')) {
    return 'The site failed on its own side ($msg).';
  }
  return msg;
}

/// "Kenosis AI - Internet Search plugin" — a separate Play Store app.
///
/// Kenosis (the offline host) binds this app's `InternetPluginService` over
/// binder and invokes its tools (browser_fetch + web_search). This screen is
/// the launcher surface: a status header plus a live log of every URL the
/// plugin has fetched on behalf of the host (open-source transparency — users
/// can see exactly what was requested). Tapping a row expands its details:
/// for a failed (red) row that means WHAT happened — a plain-language
/// explanation plus the raw reason from the service.
class KenosisPluginApp extends StatelessWidget {
  const KenosisPluginApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kenosis AI - Internet Search plugin',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const StatusScreen(),
    );
  }
}

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  static const _channel = MethodChannel('kenosis_plugin/ui');

  List<Map<String, dynamic>> _fetchLog = const [];
  Timer? _refreshTimer;

  /// Key of the expanded row (timestamp:tool:requestedUrl), NOT an index —
  /// the log is newest-first and the 2s poll can shift indexes at any time;
  /// a stable key keeps the expansion pinned to its record across polls.
  String? _expandedKey;

  @override
  void initState() {
    super.initState();
    _loadFetchLog();
    // Poll every 2s — the service may be fetching in the background while
    // the user has the plugin app open. Cheap: same-process method channel.
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadFetchLog());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFetchLog() async {
    try {
      final json = await _channel.invokeMethod<String>('getFetchLog');
      if (json == null || json.isEmpty) {
        if (_fetchLog.isNotEmpty) setState(() => _fetchLog = const []);
        return;
      }
      final list = (jsonDecode(json) as List)
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
      if (mounted) setState(() => _fetchLog = list);
    } on PlatformException catch (_) {
      // Channel not ready yet (early init) — leave the list empty.
    } on FormatException catch (_) {
      // Bad JSON — leave the list as-is.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Internet Search plugin')),
      body: SafeArea(
        child: Column(
          children: [
            // ---- Status header ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.public, size: 48, color: scheme.primary),
                  const SizedBox(height: 12),
                  const Text(
                    'Kenosis AI - Internet Search plugin',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text('Status: ready', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Text(
                    'Open Kenosis AI, tap the plugin badge in the chat and attach '
                    'this plugin to let its offline model fetch web pages on '
                    'demand. Tap any entry for details.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ---- URL log ----
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Requested URLs (${_fetchLog.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _fetchLog.isEmpty
                  ? Center(
                      child: Text(
                        'No URLs requested yet.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _fetchLog.length,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemBuilder: (context, i) {
                        final r = _fetchLog[i];
                        final isSearch = r['tool'] == 'web_search';
                        final query = r['query'] as String?;
                        final finalUrl = r['finalUrl'] as String? ?? r['requestedUrl'] as String? ?? '';
                        final title = r['title'] as String? ?? '';
                        final chars = r['chars'] as int? ?? 0;
                        final path = r['path'] as String? ?? '';
                        final status = r['status'] as String? ?? 'ok';
                        final isError = status != 'ok';
                        final ts = r['timestamp'] as int? ?? 0;
                        final time = ts > 0
                            ? DateTime.fromMillisecondsSinceEpoch(ts).toLocal()
                            : null;
                        final key = '$ts:${r['tool']}:${r['requestedUrl']}';
                        final expanded = _expandedKey == key;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: Icon(
                                isError
                                    ? Icons.error_outline
                                    : (isSearch ? Icons.search : Icons.language),
                                size: 22,
                                color: isError ? scheme.error : scheme.primary,
                              ),
                              title: Text(
                                query ?? finalUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                [
                                  if (query != null && finalUrl.isNotEmpty) finalUrl,
                                  if (title.isNotEmpty) title,
                                  if (isError)
                                    status
                                  else
                                    '$chars chars · $path',
                                  if (time != null)
                                    '${time.hour.toString().padLeft(2, '0')}:'
                                    '${time.minute.toString().padLeft(2, '0')}:'
                                    '${time.second.toString().padLeft(2, '0')}',
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isError ? scheme.error : scheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: Icon(
                                expanded ? Icons.expand_less : Icons.expand_more,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              onTap: () => setState(() {
                                _expandedKey = expanded ? null : key;
                              }),
                              isThreeLine: true,
                              dense: true,
                            ),
                            if (expanded)
                              FetchDetails(record: r, isError: isError),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expanded detail block under a log row — the "what happened" panel for a
/// failed (red) entry: plain-language explanation, raw reason from the
/// service, the URL that was attempted, and the exact time. Successful rows
/// show the same fields minus the error pair (their full URL/title is also
/// worth seeing — the collapsed row ellipsizes both).
class FetchDetails extends StatelessWidget {
  const FetchDetails({super.key, required this.record, required this.isError});

  final Map<String, dynamic> record;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tool = record['tool'] as String? ?? '';
    final query = record['query'] as String?;
    final requestedUrl = record['requestedUrl'] as String? ?? '';
    final finalUrl = record['finalUrl'] as String? ?? '';
    final title = record['title'] as String? ?? '';
    final chars = record['chars'] as int? ?? 0;
    final path = record['path'] as String? ?? '';
    final status = record['status'] as String? ?? 'ok';
    final ts = record['timestamp'] as int? ?? 0;
    final time = ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts).toLocal() : null;

    String two(int n) => n.toString().padLeft(2, '0');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isError) ...[
            _DetailRow(label: 'What happened', value: describeFetchError(status)),
            _DetailRow(label: 'Raw reason', value: status, mono: true),
          ],
          _DetailRow(label: 'Requested', value: requestedUrl),
          if (query != null && query.isNotEmpty)
            _DetailRow(label: 'Query', value: query),
          if (finalUrl.isNotEmpty && finalUrl != requestedUrl)
            _DetailRow(label: 'Redirected to', value: finalUrl),
          if (title.isNotEmpty) _DetailRow(label: 'Page title', value: title),
          if (!isError)
            _DetailRow(label: 'Served via', value: '$path · $chars chars'),
          Text(
            [
              tool,
              if (time != null)
                '${time.year}-${two(time.month)}-${two(time.day)} '
                    '${two(time.hour)}:${two(time.minute)}:${two(time.second)}',
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One label/value line of [FetchDetails]. The value is selectable so a long
/// URL or error reason can be copied out exactly.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: mono ? 'monospace' : null,
                color: mono ? scheme.error : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}