import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const mainChannel = MethodChannel('setgreet');

  List<MethodCall> recordCalls() {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(mainChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(mainChannel, null));
    return calls;
  }

  test('calls the native side without initialize', () async {
    final calls = recordCalls();

    expect(Setgreet.isInitialized, isFalse);
    await Setgreet.setLocale('tr-TR');

    expect(calls.map((c) => c.method), ['setLocale']);
    expect(calls.single.arguments, {'locale': 'tr-TR'});
  });

  test('passes null through to clear the override', () async {
    final calls = recordCalls();

    await Setgreet.setLocale(null);

    expect(calls.single.method, 'setLocale');
    expect(calls.single.arguments, {'locale': null});
  });

  test('passes an empty or unvalidated tag through unchanged', () async {
    // Clearing on empty and ignoring invalid tags is the native SDK's job.
    final calls = recordCalls();

    await Setgreet.setLocale('');
    await Setgreet.setLocale('not a locale');

    expect(calls.map((c) => c.arguments), [
      {'locale': ''},
      {'locale': 'not a locale'},
    ]);
  });

  test('wraps a platform error in a SetgreetException', () async {
    messenger.setMockMethodCallHandler(mainChannel, (call) async {
      throw PlatformException(code: 'LOCALE_ERROR', message: 'boom');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(mainChannel, null));

    expect(
      () => Setgreet.setLocale('en-US'),
      throwsA(isA<SetgreetException>()
          .having((e) => e.code, 'code', 'LOCALE_ERROR')
          .having((e) => e.message, 'message', 'boom')),
    );
  });
}
