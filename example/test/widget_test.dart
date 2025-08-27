// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('Setgreet Example App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame with a larger viewport.
    await tester.pumpWidget(
      const SizedBox(
        width: 800,
        height: 600,
        child: SetgreetExampleApp(),
      ),
    );

    // Wait for any async operations to complete
    await tester.pumpAndSettle();

    // Verify that our app shows the expected title.
    expect(find.text('Setgreet Flutter SDK'), findsOneWidget);
    expect(find.text('Setgreet SDK Example'), findsOneWidget);

    // Verify that the app key and flow ID input fields are present.
    expect(find.byType(TextField), findsNWidgets(2));

    // Verify that the buttons are present.
    expect(find.byType(ElevatedButton), findsNWidgets(5));
  });
}
