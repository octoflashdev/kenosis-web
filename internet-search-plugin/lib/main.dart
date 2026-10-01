import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const KenosisPluginApp());

/// 'qwant' → 'Qwant' for user-facing labels.
String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// One human sentence per known failure signature the service logs.
///
/// The fetch log's `status` field is "ok" (fetched page), "search" (the
/// search-engine request row — never an error), or `error:<message>` where the
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
  if (msg.contains('human check')) {
    return 'The search engine wants to verify a human before it serves '
        'results. Complete the check shown at the top of this app, then '
        'search again in Kenosis AI.';
  }
  if (msg.contains('bot protection')) {
    return 'The search engine blocked this device as a possible bot. Try a '
        'different search engine.';
  }
  if (msg.contains('WebView JS extraction returned null')) {
    return 'The page rendered, but its text could not be extracted from it.';
  }
  if (msg.contains('ERR_NAME_NOT_RESOLVED') ||
      msg.contains('Unable to resolve host')) {
    return 'The site does not exist (DNS lookup failed) — the address was '
        'wrong or made up.';
  }
  if (msg.contains('ERR_ADDRESS_UNREACHABLE') ||
      msg.contains('Failed to connect')) {
    return "The site's server could not be reached from this device's "
        'network.';
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
/// the launcher surface: a status header plus a live log of every request the
/// plugin makes on behalf of the host — search-engine requests included, not
/// just the result pages fetched after them (open-source transparency — users
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

  /// Pending human check from [CaptchaGate] (service side), polled with the
  /// same 2s channel hop as the fetch log. Null = no check pending.
  Map<String, dynamic>? _captcha;

  /// The sinceMs of the banner the user dismissed — hides the banner until a
  /// NEW gate arms (the poll would otherwise bring the dismissed one straight
  /// back every 2s).
  int? _dismissedCaptchaSince;

  /// Key of the expanded row (timestamp:tool:requestedUrl), NOT an index —
  /// the log is newest-first and the 2s poll can shift indexes at any time;
  /// a stable key keeps the expansion pinned to its record across polls.
  String? _expandedKey;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Poll every 2s — the service may be fetching in the background while
    // the user has the plugin app open. Cheap: same-process method channel.
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _loadFetchLog();
    await _loadCaptcha();
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

  Future<void> _loadCaptcha() async {
    Map<String, dynamic>? captcha;
    try {
      final json = await _channel.invokeMethod<String>('getCaptcha');
      if (json != null && json.isNotEmpty) {
        captcha = (jsonDecode(json) as Map).cast<String, dynamic>();
      }
    } on PlatformException catch (_) {
      // Channel not ready yet (early init) — no banner this tick.
    } on FormatException catch (_) {
      // Bad JSON — no banner this tick.
    }
    if (!mounted) return;
    // A dismissed gate stays hidden until a NEW one arms (different sinceMs).
    final dismissed = _dismissedCaptchaSince;
    if (captcha != null && dismissed != null && captcha['sinceMs'] == dismissed) {
      captcha = null;
    }
    setState(() => _captcha = captcha);
  }

  Future<void> _solveCaptcha() async {
    final captcha = _captcha;
    if (captcha == null) return;
    final engine = captcha['engine'] as String? ?? '';
    final url = captcha['url'] as String? ?? '';
    if (url.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CaptchaSolveScreen(engine: engine, url: url),
    ));
    // Back from the solve screen: re-poll; when the gate cleared, confirm.
    await _loadCaptcha();
    if (mounted && _captcha == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Check completed — try your search again in Kenosis AI.'),
      ));
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
            // ---- Human-check banner (+75) ----
            if (_captcha != null)
              _CaptchaBanner(
                captcha: _captcha!,
                onSolve: _solveCaptcha,
                onDismiss: () => setState(() {
                  _dismissedCaptchaSince = _captcha?['sinceMs'] as int?;
                  // Hide immediately — the next poll would otherwise keep
                  // showing the dismissed gate for up to 2s.
                  _captcha = null;
                }),
              ),
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
                  Text(
                    _captcha != null ? 'Status: human check needed' : 'Status: ready',
                    style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                  ),
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
                        // "ok" = fetched page; "search" = the engine request
                        // itself (logged, not an error); anything else is an
                        // "error:<reason>" row from the service.
                        final isSearchRequest = status == 'search';
                        final isError = status.startsWith('error:');
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
                                  else if (isSearchRequest)
                                    'search request'
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

/// Warning card at the top of the status screen — the in-plugin half of the
/// +75 captcha notification. The service armed [CaptchaGate] because an
/// engine answered a search with a bot-wall challenge; the challenge is
/// invisible inside the headless fetcher, so this banner is where the user
/// sees it and [CaptchaSolveScreen] is where they solve it.
class _CaptchaBanner extends StatelessWidget {
  const _CaptchaBanner({
    required this.captcha,
    required this.onSolve,
    required this.onDismiss,
  });

  final Map<String, dynamic> captcha;
  final VoidCallback onSolve;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final engine = _capitalize(captcha['engine'] as String? ?? 'the engine');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$engine needs a human check',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'The search engine is asking for a verification before it '
              'serves results. Complete the check, then search again in '
              'Kenosis AI.',
              style: TextStyle(fontSize: 13, color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onSolve,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Solve now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen VISIBLE WebView loaded with the exact blocked SERP URL — where
/// the user actually completes the bot-wall challenge (DataDome press-and-
/// hold, DuckDuckGo anomaly check). The system WebView's CookieManager is
/// process-wide and persisted, so the clearance cookies earned here are the
/// same cookies the plugin's hidden fetches send afterwards — that is the
/// whole mechanism (the fast OkHttp path stays fingerprint-blocked on Qwant;
/// the hidden-WebView SERP retry recovers on the earned cookie).
///
/// Auto-detects completion by reading the page's text after each navigation:
/// a real page (or a JSON body, for Qwant's API URL) is long and carries no
/// challenge markers. The Done button is the manual fallback — the detection
/// is heuristic and must never trap the user on the screen.
class CaptchaSolveScreen extends StatefulWidget {
  const CaptchaSolveScreen({super.key, required this.engine, required this.url});

  final String engine;
  final String url;

  @override
  State<CaptchaSolveScreen> createState() => _CaptchaSolveScreenState();
}

class _CaptchaSolveScreenState extends State<CaptchaSolveScreen> {
  static const _channel = MethodChannel('kenosis_plugin/ui');

  /// Read after each page load: {len, challenge} — the completion heuristic.
  /// RAW Dart string: JS needs no escaping here (no backslashes used).
  static const _challengeCheckJs = '''
(function () {
  var t = document.body ? document.body.innerText : '';
  var l = t.toLowerCase();
  var challenge = l.indexOf('press & hold') >= 0 || l.indexOf('captcha') >= 0 ||
      l.indexOf('anomaly') >= 0 || l.indexOf('verify you are a human') >= 0 ||
      l.indexOf('are you a human') >= 0;
  return JSON.stringify({len: t.length, challenge: challenge});
})()
''';

  late final WebViewController _controller;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _checkSolved(),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  /// After each navigation, decide whether the challenge is gone: enough text
  /// AND no challenge markers. On success, clear the gate (cancels the
  /// system notification — the banner disappears on the 2s poll) and pop.
  Future<void> _checkSolved() async {
    if (_finished || !mounted) return;
    try {
      final result = await _controller.runJavaScriptReturningResult(_challengeCheckJs);
      final data = (result is String)
          ? jsonDecode(result) as Map
          : result as Map;
      final len = (data['len'] as num?)?.toInt() ?? 0;
      final challenge = data['challenge'] == true;
      if (len > 400 && !challenge) {
        _finish();
      }
    } catch (_) {
      // Heuristic only — a failed read just leaves the Done button as the
      // way out; never trap the user on this screen.
    }
  }

  /// Clears [CaptchaGate] + cancels the notification, then returns to the
  /// status screen (which confirms on its next poll).
  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    try {
      await _channel.invokeMethod<void>('captchaSolved', {'engine': widget.engine});
    } on PlatformException catch (_) {
      // Channel down — the gate expires on its own TTL anyway.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _capitalize(widget.engine);
    return Scaffold(
      appBar: AppBar(
        title: Text('Complete the $engine check'),
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'If a security check appears below, complete it. When the page '
              'loads normally, the check is done — tap Done and search again '
              'in Kenosis AI.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}