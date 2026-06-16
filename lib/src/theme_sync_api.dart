import 'dart:convert';
import 'dart:io';

import 'exceptions.dart';

/// Posts an extracted Flutter theme to the Setgreet backend.
///
/// Uses the built-in `dart:io` [HttpClient] so the SDK needs no extra HTTP
/// dependency. Subclass and override [sync] in tests to assert the request
/// shape without real network I/O.
class ThemeSyncApi {
  /// Creates a const API client.
  const ThemeSyncApi();

  /// POST the theme to `<apiUrl>/sdk/sync-theme` with `platform: "flutter"`.
  ///
  /// Throws [SetgreetThemeException] on a non-2xx response or network error.
  Future<void> sync({
    required String apiUrl,
    required String appKey,
    required Map<String, String> colors,
    required Map<String, Map<String, dynamic>> typography,
    Map<String, num>? shapes,
  }) async {
    final payload = <String, dynamic>{
      'appKey': appKey,
      'platform': 'flutter',
      'colors': colors,
      if (typography.isNotEmpty) 'typography': typography,
      if (shapes != null && shapes.isNotEmpty) 'shapes': shapes,
    };

    final uri = Uri.parse('$apiUrl/sdk/sync-theme');
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final status = response.statusCode;
      if (status < 200 || status >= 300) {
        final body = await response.transform(utf8.decoder).join();
        throw SetgreetThemeException(
          'Theme sync failed ($status): $body',
          code: '$status',
        );
      }
      // Drain the response so the connection can be reused/closed cleanly.
      await response.drain<void>();
    } on SetgreetThemeException {
      rethrow;
    } catch (e) {
      throw SetgreetThemeException('Theme sync request failed: $e');
    } finally {
      client.close(force: true);
    }
  }
}
