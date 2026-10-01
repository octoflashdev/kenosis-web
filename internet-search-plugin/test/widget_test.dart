import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kenosis_plugin_internet/main.dart';

void main() {
  testWidgets('plugin status screen shows ready', (tester) async {
    await tester.pumpWidget(const KenosisPluginApp());
    expect(find.text('Status: ready'), findsOneWidget);
    expect(find.textContaining('Internet Search plugin'), findsWidgets);
  });

  group('describeFetchError — known service signatures get a human gloss', () {
    test('no-usable-result (google SERP walk empty)', () {
      expect(
        describeFetchError(
          'error:no-usable-result (IFL pick unusable, SERP walk empty)',
        ),
        contains('own app'),
      );
    });

    test('no-results (SERP parsed but zero result links)', () {
      expect(
        describeFetchError('error:no-results (serp 4211 chars)'),
        contains('no result links'),
      );
    });

    test('all-results-app-gated', () {
      expect(
        describeFetchError('error:all-results-app-gated (3 results)'),
        contains('Facebook'),
      );
    });

    test('bot protection rewrap', () {
      expect(
        describeFetchError(
          'error:the search engine blocked or could not serve its results '
          '(its bot protection may be blocking this device)',
        ),
        contains('blocked this device'),
      );
    });

    test('human check envelope maps to the in-app action (+75)', () {
      expect(
        describeFetchError(
          'error:qwant is showing a human check (captcha). Open the '
              'Internet Search plugin app, complete the check, then '
              'search again.',
        ),
        contains('Complete the check'),
      );
    });

    test('WebView JS extraction null', () {
      expect(
        describeFetchError('error:WebView JS extraction returned null'),
        contains('could not be extracted'),
      );
    });

    test('webview-reported unreachable names the dead network path (+75)', () {
      // The exact 2026-09-26 on-device string: an invented bbmedia.com URL.
      expect(
        describeFetchError(
          'error:java.lang.IllegalStateException: the page could not be '
          'loaded (net::ERR_ADDRESS_UNREACHABLE)',
        ),
        contains('could not be reached'),
      );
    });

    test('DNS failure says the address was wrong or made up (+75)', () {
      expect(
        describeFetchError(
          'error:Unable to resolve host "www.nosuchsite.example": No '
          'address associated with hostname',
        ),
        contains('made up'),
      );
    });

    test('timeout', () {
      expect(describeFetchError('error:timeout'), contains('too long'));
    });

    test('HTTP 4xx / 5xx keep the code visible', () {
      expect(describeFetchError('error:HTTP 403'), contains('403'));
      expect(describeFetchError('error:HTTP 500'), contains('500'));
    });

    test('unknown message passes through verbatim, prefix stripped', () {
      expect(
        describeFetchError('error:something new happened'),
        'something new happened',
      );
    });

    test('non-error status passes through unchanged', () {
      expect(describeFetchError('ok'), 'ok');
    });
  });

  group('fetch log details — red URLs show what happened', () {
    const channel = MethodChannel('kenosis_plugin/ui');

    String fetchLogJson() => jsonEncode([
      {
        'timestamp': 1757941440000,
        'tool': 'web_search',
        'query': 'gobekli tepe age',
        'requestedUrl': 'https://www.google.com/search?q=gobekli+tepe+age',
        'finalUrl': null,
        'title': '',
        'chars': 0,
        'path': '',
        'status': 'error:no-usable-result (IFL pick unusable, SERP walk empty)',
      },
      {
        'timestamp': 1757941400000,
        'tool': 'browser_fetch',
        'query': null,
        'requestedUrl': 'https://example.com/history',
        'finalUrl': 'https://example.com/history',
        'title': 'History',
        'chars': 1234,
        'path': 'http',
        'status': 'ok',
      },
    ]);

    Future<void> pumpScreen(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getFetchLog' ? fetchLogJson() : null,
      );
      await tester.pumpWidget(const KenosisPluginApp());
      // initState's _loadFetchLog resolves on the next pump.
      await tester.pump();
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('failed row shows the raw reason collapsed; tap expands it',
        (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // Collapsed: the raw status is already visible (truncated), but the
      // human explanation is not.
      expect(find.textContaining('no-usable-result'), findsOneWidget);
      expect(find.textContaining('own app'), findsNothing);

      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pump();
      // Expanded: gloss + raw reason (also kept in the collapsed subtitle) +
      // requested URL all visible.
      expect(find.textContaining("Google's top pick"), findsOneWidget);
      expect(find.textContaining('no-usable-result'), findsWidgets);
      expect(find.textContaining('https://www.google.com/search'), findsWidgets);
    });

    testWidgets('tapping again collapses the details', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pump();
      expect(find.textContaining("Google's top pick"), findsOneWidget);

      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pump();
      expect(find.textContaining("Google's top pick"), findsNothing);
    });

    testWidgets('successful row expands to its own (non-error) details',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byIcon(Icons.language));
      await tester.pump();
      expect(find.textContaining('Served via'), findsOneWidget);
      expect(find.textContaining('http · 1234 chars'), findsOneWidget);
      expect(find.textContaining('What happened'), findsNothing);
    });
  });

  group('human-check banner (+75) — the pending gate surfaces as a card', () {
    const channel = MethodChannel('kenosis_plugin/ui');

    String captchaJson() => jsonEncode({
      'engine': 'qwant',
      'url': 'https://api.qwant.com/v3/search/web?q=test&count=10',
      'reason': 'HTTP 403',
      'sinceMs': 1757941440000,
    });

    Future<void> pumpScreen(
      WidgetTester tester, {
      bool captcha = true,
    }) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          if (call.method == 'getFetchLog') return '[]';
          if (call.method == 'getCaptcha') return captcha ? captchaJson() : null;
          return null;
        },
      );
      await tester.pumpWidget(const KenosisPluginApp());
      // initState's _refresh (log + captcha) resolves on the next pump.
      await tester.pump();
      await tester.pump();
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('pending gate shows the banner + action-needed status',
        (tester) async {
      await pumpScreen(tester);
      expect(find.text('Qwant needs a human check'), findsOneWidget);
      expect(find.text('Status: human check needed'), findsOneWidget);
      expect(find.text('Solve now'), findsOneWidget);
    });

    testWidgets('no pending gate — plain ready screen, no banner',
        (tester) async {
      await pumpScreen(tester, captcha: false);
      expect(find.text('Qwant needs a human check'), findsNothing);
      expect(find.text('Status: ready'), findsOneWidget);
    });

    testWidgets('dismiss hides the banner until a NEW gate arms',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      await tester.pump();
      // The poll keeps returning the SAME gate (same sinceMs) — stays hidden.
      expect(find.text('Qwant needs a human check'), findsNothing);
      expect(find.text('Status: ready'), findsOneWidget);
    });
  });
}