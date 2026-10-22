import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const mainChannel = MethodChannel('setgreet');

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(mainChannel, handler);
    addTearDown(() => messenger.setMockMethodCallHandler(mainChannel, null));
  }

  test('calls the native side without initialize and returns true', () async {
    final calls = <MethodCall>[];
    mockChannel((call) async {
      calls.add(call);
      return true;
    });

    expect(Setgreet.isInitialized, isFalse);
    expect(await Setgreet.registerLottie(), isTrue);
    expect(calls.map((c) => c.method), ['registerLottie']);
    expect(calls.single.arguments, isNull);
  });

  test('returns false when the native Lottie module is not installed',
      () async {
    mockChannel((call) async => false);

    expect(await Setgreet.registerLottie(), isFalse);
  });

  test('returns false on a platform error or a null reply', () async {
    mockChannel((call) async => throw PlatformException(code: 'ERROR'));
    expect(await Setgreet.registerLottie(), isFalse);

    mockChannel((call) async => null);
    expect(await Setgreet.registerLottie(), isFalse);
  });

  test('returns false when no native plugin answers the call', () async {
    mockChannel((call) async => throw MissingPluginException());
    expect(await Setgreet.registerLottie(), isFalse);

    // No handler at all: the platform channel itself reports the plugin missing.
    messenger.setMockMethodCallHandler(mainChannel, null);
    expect(await Setgreet.registerLottie(), isFalse);
  });
}
