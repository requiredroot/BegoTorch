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

void main() {
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

    test('an existing binary yields a ProcessResult, not an exception', () async {
      // /bin/false runs and exits non-zero: exactly the case the resolver
      // must treat as "su exists" rather than skipping the candidate.
      final ProcessResult result = await Process.run(
        '/bin/false',
        const <String>[],
        runInShell: false,
      );
      expect(result.exitCode, isNot(0));
    });
  });

  testWidgets('renders the torch dial and initial value', (WidgetTester tester) async {
    await tester.pumpWidget(const BegoTorchApp());

    expect(find.text('Torch'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is CustomPaint && w.painter != null,
      ),
      findsOneWidget,
    );
  });
}

