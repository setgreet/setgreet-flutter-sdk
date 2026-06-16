import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

void main() {
  /// Pumps a widget under a MaterialApp with [theme] and runs [body] with the
  /// BuildContext below the MaterialApp (so Theme.of resolves the app theme).
  Future<void> withTheme(
    WidgetTester tester,
    ThemeData theme,
    void Function(BuildContext context) body,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            body(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  group('ThemeExtractor.extractColors', () {
    testWidgets('emits the seed-derived primary as #RRGGBB', (tester) async {
      final theme = ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1F8A5B),
          onPrimary: Color(0xFFFFFFFF),
          surface: Color(0xFFFAFAFA),
          onSurface: Color(0xFF1A1A1A),
        ),
      );
      await withTheme(tester, theme, (context) {
        final colors = ThemeExtractor.extractColors(context);
        expect(colors['primary'], '#1F8A5B');
        expect(colors['onPrimary'], '#FFFFFF');
        expect(colors['surface'], '#FAFAFA');
        expect(colors['onSurface'], '#1A1A1A');
        // Hex is always uppercase, 6 digits for opaque colors.
        expect(colors['primary'], matches(r'^#[0-9A-F]{6}$'));
      });
    });

    testWidgets('includes the core Material 3 roles', (tester) async {
      await withTheme(tester, ThemeData(), (context) {
        final colors = ThemeExtractor.extractColors(context);
        for (final role in [
          'primary',
          'onPrimary',
          'secondary',
          'surface',
          'onSurface',
          'error',
          'outline',
        ]) {
          expect(colors.containsKey(role), isTrue, reason: 'missing $role');
        }
      });
    });

    testWidgets('drops alpha — always emits 6-digit #RRGGBB', (tester) async {
      // A translucent color must NOT become #AARRGGBB (which iOS and Android
      // read with opposite alpha order). Alpha is dropped to match the natives.
      final theme = ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0x801F8A5B), // 50% alpha
        ),
      );
      await withTheme(tester, theme, (context) {
        final colors = ThemeExtractor.extractColors(context);
        expect(colors['primary'], '#1F8A5B');
        expect(colors['primary'], matches(r'^#[0-9A-F]{6}$'));
      });
    });
  });

  group('ThemeExtractor.extractTypography', () {
    testWidgets('maps font size and weight, omitting empty entries',
        (tester) async {
      final theme = ThemeData(
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.4,
            letterSpacing: 0.25,
          ),
        ),
      );
      await withTheme(tester, theme, (context) {
        final typo = ThemeExtractor.extractTypography(context);
        final body = typo['bodyMedium']!;
        expect(body['fontFamily'], 'Roboto');
        expect(body['fontSize'], 14.0);
        expect(body['fontWeight'], 500); // FontWeight.w500.value
        expect(body['lineHeight'], 1.4);
        expect(body['letterSpacing'], 0.25);
        // fontWeight must be a valid backend weight (100..900, multiple of 100).
        expect((body['fontWeight'] as int) % 100, 0);
      });
    });
  });
}
