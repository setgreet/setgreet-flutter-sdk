import 'package:flutter/material.dart';

/// Extracts Material 3 theme data from a [BuildContext] and converts it
/// to a serializable map suitable for the Setgreet sync-theme API.
///
/// Flutter draws its UI from its own [ThemeData] (in the Dart layer), which
/// the native iOS/Android SDKs cannot see — their auto-sync reads the host
/// platform theme (UIKit system colors / the Android Activity theme), which
/// for a Flutter app is framework defaults, not the app's real palette. So a
/// Flutter app must extract and sync its [ThemeData] explicitly.
class ThemeExtractor {
  /// Extracts the full color scheme from the current theme.
  ///
  /// Reads the Material 3 color roles from [ColorScheme] and converts each
  /// [Color] to a hex string. The backend accepts any subset of roles.
  static Map<String, String> extractColors(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return {
      'primary': _colorToHex(colorScheme.primary),
      'onPrimary': _colorToHex(colorScheme.onPrimary),
      'primaryContainer': _colorToHex(colorScheme.primaryContainer),
      'onPrimaryContainer': _colorToHex(colorScheme.onPrimaryContainer),
      'secondary': _colorToHex(colorScheme.secondary),
      'onSecondary': _colorToHex(colorScheme.onSecondary),
      'secondaryContainer': _colorToHex(colorScheme.secondaryContainer),
      'onSecondaryContainer': _colorToHex(colorScheme.onSecondaryContainer),
      'tertiary': _colorToHex(colorScheme.tertiary),
      'onTertiary': _colorToHex(colorScheme.onTertiary),
      'tertiaryContainer': _colorToHex(colorScheme.tertiaryContainer),
      'onTertiaryContainer': _colorToHex(colorScheme.onTertiaryContainer),
      'surface': _colorToHex(colorScheme.surface),
      'onSurface': _colorToHex(colorScheme.onSurface),
      'surfaceContainerHighest':
          _colorToHex(colorScheme.surfaceContainerHighest),
      'onSurfaceVariant': _colorToHex(colorScheme.onSurfaceVariant),
      'error': _colorToHex(colorScheme.error),
      'onError': _colorToHex(colorScheme.onError),
      'errorContainer': _colorToHex(colorScheme.errorContainer),
      'onErrorContainer': _colorToHex(colorScheme.onErrorContainer),
      'outline': _colorToHex(colorScheme.outline),
      'outlineVariant': _colorToHex(colorScheme.outlineVariant),
      'inverseSurface': _colorToHex(colorScheme.inverseSurface),
      'onInverseSurface': _colorToHex(colorScheme.onInverseSurface),
      'inversePrimary': _colorToHex(colorScheme.inversePrimary),
    };
  }

  /// Extracts the Material 3 type scale entries from the current theme.
  ///
  /// Each entry includes fontFamily, fontSize, fontWeight (100-900),
  /// lineHeight (as a multiplier), and letterSpacing. Empty entries are
  /// omitted so the payload only carries styles the theme actually defines.
  static Map<String, Map<String, dynamic>> extractTypography(
    BuildContext context,
  ) {
    final textTheme = Theme.of(context).textTheme;

    final entries = <String, TextStyle?>{
      'displayLarge': textTheme.displayLarge,
      'displayMedium': textTheme.displayMedium,
      'displaySmall': textTheme.displaySmall,
      'headlineLarge': textTheme.headlineLarge,
      'headlineMedium': textTheme.headlineMedium,
      'headlineSmall': textTheme.headlineSmall,
      'titleLarge': textTheme.titleLarge,
      'titleMedium': textTheme.titleMedium,
      'titleSmall': textTheme.titleSmall,
      'bodyLarge': textTheme.bodyLarge,
      'bodyMedium': textTheme.bodyMedium,
      'bodySmall': textTheme.bodySmall,
      'labelLarge': textTheme.labelLarge,
      'labelMedium': textTheme.labelMedium,
      'labelSmall': textTheme.labelSmall,
    };

    final result = <String, Map<String, dynamic>>{};
    entries.forEach((name, style) {
      final map = _textStyleToMap(style);
      if (map.isNotEmpty) {
        result[name] = map;
      }
    });
    return result;
  }

  /// Converts a [Color] to a 6-digit `#RRGGBB` hex string.
  ///
  /// Alpha is intentionally dropped, matching the native iOS and Android SDKs.
  /// 8-digit hex is ambiguous across the stack — iOS reads it as `#AARRGGBB`
  /// (alpha first) while Android and the web editor read `#RRGGBBAA` (alpha
  /// last) — so the same translucent value would render differently per
  /// platform. Theme brand colors are effectively always opaque, so emitting
  /// only `#RRGGBB` keeps theme sync consistent everywhere.
  static String _colorToHex(Color color) {
    final int r = (color.r * 255.0).round().clamp(0, 255);
    final int g = (color.g * 255.0).round().clamp(0, 255);
    final int b = (color.b * 255.0).round().clamp(0, 255);
    return '#${_hex(r)}${_hex(g)}${_hex(b)}';
  }

  /// Converts a single channel value (0-255) to a two-character hex string.
  static String _hex(int value) {
    return value.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  /// Converts a nullable [TextStyle] to a serializable map.
  ///
  /// Returns an empty map if the style is null or carries no usable fields.
  static Map<String, dynamic> _textStyleToMap(TextStyle? style) {
    if (style == null) return {};

    final map = <String, dynamic>{};

    if (style.fontFamily != null) {
      map['fontFamily'] = style.fontFamily;
    }
    if (style.fontSize != null) {
      map['fontSize'] = style.fontSize;
    }
    if (style.fontWeight != null) {
      // FontWeight.value is already the numeric 100-900 weight the backend wants.
      map['fontWeight'] = style.fontWeight!.value;
    }
    if (style.height != null) {
      map['lineHeight'] = style.height;
    }
    if (style.letterSpacing != null) {
      map['letterSpacing'] = style.letterSpacing;
    }

    return map;
  }
}
