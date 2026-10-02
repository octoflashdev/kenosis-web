import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'legal/legal_document_repository.dart';
import 'legal/legal_document_repository_impl.dart';
import 'presentation/views/about_screen.dart';
import 'presentation/views/plugin_drawer.dart';
import 'presentation/widgets/theme_scope.dart';
import 'services/external_links_service.dart';
import 'services/external_links_service_impl.dart';
import 'services/theme_service.dart';
import 'services/theme_service_impl.dart';
import 'storage/secure_storage_adapter.dart';

/// This plugin's public source tree on GitHub (About → Report bug).
const String kLivecastSourceUrl =
    'https://github.com/octoflashdev/kenosis-web/tree/main/livecast-plugin';

void main() => runApp(const KenosisPluginApp());

/// "Kenosis AI - LiveCast plugin" — a separate app bound by the offline
/// Kenosis host over binder. Serves the realtime lecture transcription page
/// to any device on the same Wi-Fi (NanoHTTPD :8090). This screen is the
/// launcher surface: live server/session status read from the in-process
/// service.
///
/// The app widget is the plugin's composition root (the host's main.dart
/// role): it owns the [ThemeService] and the [LegalDocumentRepository] and
/// injects them down the tree via constructors — the plugin apps have no
/// service locator. All three seams are optional so widget tests can inject
/// fakes.
class KenosisPluginApp extends StatefulWidget {
  const KenosisPluginApp({
    super.key,
    this.themeService,
    this.legalRepository,
    this.linksService,
  });

  /// Injectable for tests; production builds use the encrypted-KV-backed
  /// service (light/dark/auto, persisted, defaults to following the system).
  final ThemeService? themeService;

  /// Injectable for tests; production builds load the bundled legal assets.
  final LegalDocumentRepository? legalRepository;

  /// Injectable for tests; production builds speak over the plugin's UI
  /// channel (Play Store hand-off after the confirm alert).
  final ExternalLinksService? linksService;

  @override
  State<KenosisPluginApp> createState() => _KenosisPluginAppState();
}

class _KenosisPluginAppState extends State<KenosisPluginApp> {
  late final ThemeService _theme =
      widget.themeService ?? ThemeServiceImpl(SecureStorageAdapter());
  late final LegalDocumentRepository _legal =
      widget.legalRepository ?? LegalDocumentRepositoryImpl();
  late final ExternalLinksService _links = widget.linksService ??
      ChannelExternalLinksService(const MethodChannel('kenosis_livecast/ui'));

  @override
  void initState() {
    super.initState();
    // Hydrate the persisted theme mode (default: follow the system). Storage
    // hiccups (channel missing in widget tests, a broken Keystore on device)
    // degrade to the default mode — never crash the app.
    unawaited(_theme.hydrate().catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole MaterialApp when the user toggles light/dark/auto in
    // the drawer switcher (the host's +69 pattern).
    return ListenableBuilder(
      listenable: _theme.modeListenable,
      builder: (context, _) => MaterialApp(
        title: 'Kenosis AI - LiveCast plugin',
        themeMode: _theme.currentMode,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        // ThemeScope carries the mode listenable + setter into the tree so
        // the drawer switcher stays a thin view (no service-locator lookup).
        builder: (context, child) => ThemeScope(
          modeListenable: _theme.modeListenable,
          onChanged: _theme.setMode,
          child: child!,
        ),
        home: StatusScreen(
          legalRepository: _legal,
          linksService: _links,
          appTitle: 'LiveCast plugin',
          identityIcon: Icons.graphic_eq,
          privacyLine: 'The live transcript page is served only to devices '
              'on YOUR Wi-Fi — nothing is sent to the app maker or any '
              'third party.',
          sourceUrl: kLivecastSourceUrl,
        ),
      ),
    );
  }
}

class StatusScreen extends StatefulWidget {
  const StatusScreen({
    super.key,
    required this.legalRepository,
    required this.linksService,
    required this.appTitle,
    required this.identityIcon,
    required this.privacyLine,
    required this.sourceUrl,
  });

  final LegalDocumentRepository legalRepository;

  /// Play Store hand-off behind the confirm alert (drawer + About).
  final ExternalLinksService linksService;

  /// The plugin's short name (drawer header / About title).
  final String appTitle;

  /// The plugin's identity icon (status header + About).
  final IconData identityIcon;

  /// The one-sentence privacy claim shown in About.
  final String privacyLine;

  /// This plugin's public source tree (About → Report bug).
  final String sourceUrl;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  static const _channel = MethodChannel('kenosis_livecast/ui');

  Map<String, dynamic> _status = const {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    // Poll every 2s — the host may be pushing segments while the user has
    // the plugin app open. Cheap: same-process method channel.
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final json = await _channel.invokeMethod<String>('getStatus');
      if (json == null || json.isEmpty) return;
      final map = (jsonDecode(json) as Map).cast<String, dynamic>();
      if (mounted) setState(() => _status = map);
    } on PlatformException catch (_) {
      // Channel not ready yet (early init) — leave the status empty.
    } on FormatException catch (_) {
      // Bad JSON — leave the status as-is.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final serverRunning = _status['serverRunning'] == true;
    final port = _status['port'] as int? ?? -1;
    final segments = _status['segments'] as int? ?? 0;
    final digests = _status['digests'] as int? ?? 0;
    final elapsedMs = _status['sessionElapsedMs'] as int? ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('LiveCast plugin')),
      // Shell drawer (host ChatHistoryDrawer shape): theme switcher, the
      // main-app hand-off, and the legal pages. Flutter draws the hamburger
      // automatically once a drawer is set. No delete-all badge here — the
      // status screen has no log.
      drawer: PluginDrawer(
        legalRepository: widget.legalRepository,
        linksService: widget.linksService,
        appTitle: widget.appTitle,
        aboutScreen: AboutScreen(
          legalRepository: widget.legalRepository,
          linksService: widget.linksService,
          appTitle: 'Kenosis AI - ${widget.appTitle}',
          icon: widget.identityIcon,
          privacyLine: widget.privacyLine,
          privacyIcon: Icons.wifi,
          sourceUrl: widget.sourceUrl,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.graphic_eq, size: 48, color: scheme.primary),
              const SizedBox(height: 12),
              const Text(
                'Kenosis AI - LiveCast plugin',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                serverRunning
                    ? 'Serving the transcript page on port $port'
                    : 'Status: ready (waiting for a host session)',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Start a LiveCast session in Kenosis AI and open '
                'http://<this-device-ip>:$port on any device on the same '
                'Wi-Fi to follow the live transcript.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              _row(context, 'Session elapsed', _formatElapsed(elapsedMs)),
              _row(context, 'Segments held', '$segments'),
              _row(context, 'Digest cards', '$digests'),
              _row(context, 'Web server',
                  serverRunning ? 'running :$port' : 'stopped'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontFeatures: [])),
        ],
      ),
    );
  }

  static String _formatElapsed(int ms) {
    final totalSec = ms ~/ 1000;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    final h = m ~/ 60;
    return h > 0
        ? '$h:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '$m:${s.toString().padLeft(2, '0')}';
  }
}
