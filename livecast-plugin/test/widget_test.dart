import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kenosis_plugin_livecast/legal/legal_document.dart';
import 'package:kenosis_plugin_livecast/legal/legal_document_repository.dart';
import 'package:kenosis_plugin_livecast/main.dart';
import 'package:kenosis_plugin_livecast/services/external_links_service.dart';
import 'package:kenosis_plugin_livecast/services/theme_service.dart';

class FakeThemeService implements ThemeService {
  FakeThemeService([ThemeMode initial = ThemeMode.system]);

  final ValueNotifier<ThemeMode> _mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  @override
  ThemeMode get currentMode => _mode.value;

  @override
  ValueListenable<ThemeMode> get modeListenable => _mode;

  @override
  Future<void> setMode(ThemeMode mode) async {
    _mode.value = mode;
  }

  @override
  Future<void> hydrate() async {}
}

class FakeLegalDocumentRepository implements LegalDocumentRepository {
  const FakeLegalDocumentRepository(this.body);
  final String body;

  @override
  Future<String> load(LegalDocument document) async => body;
}

class FakeLinksService implements ExternalLinksService {
  final opened = <String>[];
  bool succeed = true;

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return succeed;
  }
}

void main() {
  // NOTE: never pumpAndSettle here — StatusScreen polls every 2 s (Timer),
  // so the frame pipeline never settles. Pump fixed durations instead.
  const routePump = Duration(milliseconds: 400);

  testWidgets('plugin status screen shows ready', (tester) async {
    await tester.pumpWidget(const KenosisPluginApp());
    // The idle status line is "Status: ready (waiting for a host session)" —
    // match by prefix (the pre-shell test asserted the exact short string and
    // could never have passed; plugin tests run in no CI).
    expect(find.textContaining('Status: ready'), findsOneWidget);
    expect(find.textContaining('LiveCast plugin'), findsWidgets);
  });

  group('plugin shell — drawer, theme, legal pages', () {
    const legalBody =
        '# Privacy Notice\nThe transcript is served only to devices\non '
        'your Wi-Fi. Nothing else.';

    Future<void> pumpApp(
      WidgetTester tester, {
      ThemeService? theme,
      String legal = legalBody,
      FakeLinksService? links,
    }) async {
      await tester.pumpWidget(KenosisPluginApp(
        themeService: theme ?? FakeThemeService(),
        legalRepository: FakeLegalDocumentRepository(legal),
        linksService: links ?? FakeLinksService(),
      ));
      await tester.pump();
      await tester.pump();
    }

    Future<void> openDrawer(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(routePump);
    }

    testWidgets('drawer opens with the main-app hand-off and legal pages',
        (tester) async {
      await pumpApp(tester);
      await openDrawer(tester);

      expect(find.text('LiveCast plugin'), findsWidgets);
      expect(find.text('Get Kenosis AI (main app)'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Privacy Notice'), findsOneWidget);
      expect(find.text('App permissions'), findsOneWidget);
      expect(find.text('Open-source licenses'), findsOneWidget);
    });

    testWidgets('theme switcher re-themes the app (system → dark)',
        (tester) async {
      final theme = FakeThemeService();
      await pumpApp(tester, theme: theme);
      await openDrawer(tester);

      expect(theme.currentMode, ThemeMode.system);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );

      await tester.tap(find.byTooltip('Theme'));
      await tester.pump();
      await tester.pump(routePump);
      await tester.tap(find.text('Dark'));
      await tester.pump();
      await tester.pump(routePump);

      expect(theme.currentMode, ThemeMode.dark);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
    });

    testWidgets('Get Kenosis AI: warn dialog, OK opens the Play listing',
        (tester) async {
      final links = FakeLinksService();
      await pumpApp(tester, links: links);
      await openDrawer(tester);

      await tester.tap(find.text('Get Kenosis AI (main app)'));
      await tester.pump();
      await tester.pump(routePump);

      // The alert WARNS what OK will do (open Google Play); no store page
      // may launch without it. The site address stays plain selectable text.
      expect(find.text('Get Kenosis AI'), findsOneWidget);
      expect(find.textContaining('Google Play'), findsWidgets);
      expect(find.text('www.kenosis-ai.com'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(links.opened, isEmpty);

      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(routePump);

      expect(links.opened, [kenosisAiPlayStoreUrl]);
    });

    testWidgets('Get Kenosis AI: a failed store launch degrades to a SnackBar',
        (tester) async {
      final links = FakeLinksService()..succeed = false;
      await pumpApp(tester, links: links);
      await openDrawer(tester);

      await tester.tap(find.text('Get Kenosis AI (main app)'));
      await tester.pump();
      await tester.pump(routePump);
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(routePump);

      expect(find.textContaining('Could not open the Play Store'),
          findsOneWidget);
    });

    testWidgets('About renders the Wi-Fi privacy line, version and legal tiles',
        (tester) async {
      await pumpApp(tester);
      await openDrawer(tester);

      await tester.tap(find.text('About'));
      await tester.pump();
      await tester.pump(routePump);

      expect(find.textContaining('companion plugin of Kenosis AI'),
          findsOneWidget);
      expect(find.text('v0.1.1+2'), findsOneWidget);
      // The Play hand-off row is present; the site URL stays plain text.
      expect(find.text('Kenosis AI on Google Play'), findsOneWidget);
      expect(find.text('www.kenosis-ai.com'), findsOneWidget);
      // The list is taller than the test viewport (lazy ListView) — walk it
      // section by section.
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Open-source licenses'), 200, scrollable: scrollable);
      expect(find.text('Privacy Notice'), findsOneWidget);
      expect(find.text('App permissions'), findsOneWidget);
      expect(find.text('Open-source licenses'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('octoflash.sup@gmail.com'), 200, scrollable: scrollable);
      expect(find.text('octoflash.sup@gmail.com'), findsOneWidget);
    });

    testWidgets('About Play row opens the listing only after the confirm alert',
        (tester) async {
      final links = FakeLinksService();
      await pumpApp(tester, links: links);
      await openDrawer(tester);
      await tester.tap(find.text('About'));
      await tester.pump();
      await tester.pump(routePump);

      await tester.tap(find.text('Kenosis AI on Google Play'));
      await tester.pump();
      await tester.pump(routePump);

      // Alert first — nothing opens without OK.
      expect(find.text('Open Google Play?'), findsOneWidget);
      expect(links.opened, isEmpty);

      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(routePump);
      expect(links.opened, [kenosisAiPlayStoreUrl]);
    });

    testWidgets('About report-bug section names this plugin\'s source tree',
        (tester) async {
      await pumpApp(tester);
      await openDrawer(tester);
      await tester.tap(find.text('About'));
      await tester.pump();
      await tester.pump(routePump);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.textContaining('tree/main/livecast-plugin'), 200,
        scrollable: scrollable);
      expect(find.textContaining('tree/main/livecast-plugin'), findsOneWidget);
      // Plain selectable text, not a button — nothing else is tappable.
      expect(find.text('octoflash.sup@gmail.com'), findsOneWidget);
    });

    testWidgets('privacy notice joins hard-wrapped source lines into one paragraph',
        (tester) async {
      await pumpApp(tester);
      await openDrawer(tester);

      await tester.tap(find.text('Privacy Notice'));
      await tester.pump();
      await tester.pump(routePump);

      // The two physical lines render as ONE continuous sentence (soft-wrap
      // joining), not two fragments. Paragraphs are RichText blocks.
      final paragraphs = tester.widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text.toPlainText())
          .toList();
      expect(
        paragraphs,
        contains('The transcript is served only to devices on your Wi-Fi. '
            'Nothing else.'),
      );
    });

    testWidgets('app permissions lists the single manifest row', (tester) async {
      await pumpApp(tester);
      await openDrawer(tester);

      await tester.tap(find.text('App permissions'));
      await tester.pump();
      await tester.pump(routePump);

      // Livecast's manifest declares INTERNET only — no POST_NOTIFICATIONS.
      expect(find.text('INTERNET'), findsOneWidget);
      expect(find.text('POST_NOTIFICATIONS'), findsNothing);
    });

    testWidgets('licenses render the bundled text verbatim monospace',
        (tester) async {
      const licenseText = 'Apache License\n   Version 2.0, January 2004';
      await pumpApp(tester, legal: licenseText);
      await openDrawer(tester);

      await tester.tap(find.text('Open-source licenses'));
      await tester.pump();
      await tester.pump(routePump);

      final body = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('Version 2.0'),
      ));
      expect(body.softWrap, false, reason: 'license renders verbatim, not wrapped');
      expect(body.style?.fontFamily, 'monospace');
    });
  });
}
