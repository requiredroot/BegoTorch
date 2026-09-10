// Tests for BegoTorch.
//
// The widget smoke test never taps the dial, so no `su` probe can fire on CI.
// The su-path resolution contract is covered by pure unit tests over the
// public `kSuCandidates` list plus the dart:io behavior the resolver relies
// on (missing binary => ProcessException, existing binary => ProcessResult).

import 'dart:io';

import 'package:begotorch/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    // SharedPreferences needs a mock before any widget that reads it
    // is pumped. Set up a global mock with no saved values.
    SharedPreferences.setMockInitialValues({});
  });

  group('su candidate list', () {
    test('does not contain the Linux-only /bin/su path', () {
      // /bin does not exist on Android; hardcoding it was the cause of
      // "Failed to run su: No such file or directory".
      expect(kSuCandidates, isNot(contains('/bin/su')));
    });

    test('starts with the standard Android su location', () {
      expect(kSuCandidates.first, '/system/bin/su');
    });

    test('covers the APatch/FolkPatch binary dir', () {
      expect(kSuCandidates, contains('/data/adb/ap/bin/su'));
    });

    test('covers the other common superuser locations', () {
      expect(kSuCandidates, contains('/system/xbin/su'));
      expect(kSuCandidates, contains('/su/bin/su'));
      expect(kSuCandidates, contains('/sbin/su'));
      expect(kSuCandidates, contains('/magisk/.core/bin/su'));
    });

    test('has no duplicates', () {
      expect(kSuCandidates.toSet().length, kSuCandidates.length);
    });
  });

  group('su probing prerequisites', () {
    test('a missing binary raises ProcessException', () async {
      await expectLater(
        Process.run(
          '/nonexistent/begotorch-probe',
          const <String>[],
          runInShell: false,
        ),
        throwsA(isA<ProcessException>()),
      );
    });

    test(
      'an existing binary yields a ProcessResult, not an exception',
      () async {
        // /bin/false runs and exits non-zero: exactly the case the resolver
        // must treat as "su exists" rather than skipping the candidate.
        final ProcessResult result = await Process.run(
          '/bin/false',
          const <String>[],
          runInShell: false,
        );
        expect(result.exitCode, isNot(0));
      },
    );
  });

  testWidgets('renders the torch dial and initial value', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BegoTorchApp());

    expect(find.text('Torch'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // The dial is rendered as a CustomPaint with a _DialPainter, identifiable
    // by its key.
    expect(find.byKey(const ValueKey<String>('torch_dial')), findsOneWidget);
  });

  group('settings / icon chooser', () {
    testWidgets('navigates to settings and shows icon variants', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const BegoTorchApp());

      // Tap the settings icon in the app bar.
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Settings page title is visible.
      expect(find.text('Settings'), findsOneWidget);

      // All built-in icon variants are offered.
      for (final TorchIcon icon in kTorchIcons) {
        expect(find.text(icon.label), findsOneWidget);
      }

      // The default selection is 'Selected' next to the first icon.
      expect(find.text('Selected'), findsOneWidget);
    });

    testWidgets('selecting an icon persists it and shows it on home', (
      WidgetTester tester,
    ) async {
      // SharedPreferences needs a mock in tests.
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const BegoTorchApp());

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // kTorchIcons order: torch, star, moon, sun.
      // Tap the Star variant (the tap target is the RadioListTile itself).
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('icon_option_star')),
          matching: find.text('Star'),
        ),
      );
      await tester.pumpAndSettle();

      // 'Star' should now be the selected one (only one 'Selected' label),
      // and the stored preference must match the tapped variant.
      expect(find.text('Selected'), findsOneWidget);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefIcon), 'star');

      // Returning to home must show the persisted choice.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Star'), findsOneWidget);
    });

    test('iconForId returns the first icon for an unknown id', () {
      expect(iconForId('nonexistent'), same(kTorchIcons.first));
    });

    test('iconForId returns the matching variant', () {
      expect(iconForId('moon'), same(kTorchIcons[2]));
      expect(iconForId('torch'), same(kTorchIcons.first));
    });

    test('kTorchIcons is non-empty and has unique ids', () {
      expect(kTorchIcons, isNotEmpty);
      final ids = kTorchIcons.map((i) => i.id).toSet();
      expect(ids.length, kTorchIcons.length);
    });
  });
}
