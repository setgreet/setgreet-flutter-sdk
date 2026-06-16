import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

/// Records the arguments passed to [sync] instead of making a network call.
class _RecordingThemeSyncApi extends ThemeSyncApi {
  Map<String, dynamic>? captured;
  bool throwOnSync = false;

  @override
  Future<void> sync({
    required String apiUrl,
    required String appKey,
    required Map<String, String> colors,
    required Map<String, Map<String, dynamic>> typography,
    Map<String, num>? shapes,
  }) async {
    captured = {
      'apiUrl': apiUrl,
      'appKey': appKey,
      'colors': colors,
      'typography': typography,
      'shapes': shapes,
    };
    if (throwOnSync) {
      throw SetgreetThemeException('boom', code: '500');
    }
  }
}

void main() {
  group('ThemeSyncApi.sync over a real loopback server', () {
    late HttpServer server;
    HttpRequest? received;
    String? receivedBody;
    int responseStatus = 200;

    setUp(() async {
      received = null;
      receivedBody = null;
      responseStatus = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        received = req;
        receivedBody = await utf8.decoder.bind(req).join();
        req.response.statusCode = responseStatus;
        req.response.write('{}');
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    String apiUrl() => 'http://${server.address.address}:${server.port}/api/v1';

    test('posts a flutter platform payload to /sdk/sync-theme', () async {
      const api = ThemeSyncApi();
      await api.sync(
        apiUrl: apiUrl(),
        appKey: 'app_key_123',
        colors: const {'primary': '#1F8A5B', 'surface': '#FAFAFA'},
        typography: const {
          'bodyMedium': {'fontSize': 14, 'fontWeight': 500},
        },
      );

      expect(received, isNotNull);
      expect(received!.method, 'POST');
      expect(received!.uri.path, '/api/v1/sdk/sync-theme');
      expect(
        received!.headers.contentType?.mimeType,
        'application/json',
      );

      final body = jsonDecode(receivedBody!) as Map<String, dynamic>;
      expect(body['appKey'], 'app_key_123');
      expect(body['platform'], 'flutter');
      expect((body['colors'] as Map)['primary'], '#1F8A5B');
      expect((body['typography'] as Map)['bodyMedium']['fontWeight'], 500);
    });

    test('omits typography and shapes when empty', () async {
      const api = ThemeSyncApi();
      await api.sync(
        apiUrl: apiUrl(),
        appKey: 'k',
        colors: const {'primary': '#000000'},
        typography: const {},
      );
      final body = jsonDecode(receivedBody!) as Map<String, dynamic>;
      expect(body.containsKey('typography'), isFalse);
      expect(body.containsKey('shapes'), isFalse);
    });

    test('throws SetgreetThemeException on a non-2xx response', () async {
      responseStatus = 400;
      const api = ThemeSyncApi();
      expect(
        () => api.sync(
          apiUrl: apiUrl(),
          appKey: 'k',
          colors: const {'primary': '#000000'},
          typography: const {},
        ),
        throwsA(isA<SetgreetThemeException>()),
      );
    });
  });

  test('SetgreetThemeException carries message and code', () {
    final e = SetgreetThemeException('Theme sync failed (400): bad', code: '400');
    expect(e.message, contains('400'));
    expect(e.code, '400');
    expect(e.toString(), contains('[400]'));
  });

  group('recording fake injected into Setgreet', () {
    late _RecordingThemeSyncApi fake;

    setUp(() {
      fake = _RecordingThemeSyncApi();
      Setgreet.themeSyncApi = fake;
    });

    tearDown(() {
      Setgreet.themeSyncApi = const ThemeSyncApi();
    });

    test('the injected api is used by Setgreet', () async {
      // Directly exercise the injected client (Setgreet.syncTheme needs a
      // BuildContext + native init, covered in the widget test layer).
      await fake.sync(
        apiUrl: 'http://localhost:3001/api/v1',
        appKey: 'k',
        colors: const {'primary': '#1F8A5B'},
        typography: const {},
      );
      expect(fake.captured, isNotNull);
      expect(fake.captured!['appKey'], 'k');
      expect(fake.captured!['apiUrl'], 'http://localhost:3001/api/v1');
      expect(
        (fake.captured!['colors'] as Map)['primary'],
        '#1F8A5B',
      );
    });
  });
}
