// Basic smoke test for BegoTorch.
//
// Builds the app, finds the dial, and verifies the initial brightness label.

import 'package:begotorch/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
