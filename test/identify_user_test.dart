import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const mainChannel = MethodChannel('setgreet');
  const eventChannel = MethodChannel('setgreet/events');
  final calls = <MethodCall>[];

  setUpAll(() async {
    messenger.setMockMethodCallHandler(mainChannel, (call) async {
      calls.add(call);
      return null;
    });
    // `initialize` starts listening for flow events.
    messenger.setMockMethodCallHandler(eventChannel, (call) async => null);
    await Setgreet.initialize('app-key');
  });

  tearDownAll(() {
    messenger.setMockMethodCallHandler(mainChannel, null);
    messenger.setMockMethodCallHandler(eventChannel, null);
  });

  setUp(calls.clear);

  test('forwards userHash to the native side', () async {
    await Setgreet.identifyUser(
      'user_123',
      attributes: {'plan': 'pro'},
      userHash: 'a1b2c3',
    );

    expect(calls.single.method, 'identifyUser');
    expect(calls.single.arguments, {
      'userId': 'user_123',
      'attributes': {'plan': 'pro'},
      'operation': 'create',
      'locale': null,
      'userHash': 'a1b2c3',
    });
  });

  test('sends a null userHash when it is omitted', () async {
    await Setgreet.identifyUser('user_123',
        operation: 'update', locale: 'en-US');

    expect(calls.single.arguments, {
      'userId': 'user_123',
      'attributes': <String, dynamic>{},
      'operation': 'update',
      'locale': 'en-US',
      'userHash': null,
    });
  });

  test('passes userHash through unchanged (the native SDK ignores a blank one)',
      () async {
    await Setgreet.identifyUser('user_123', userHash: '');

    expect((calls.single.arguments as Map)['userHash'], '');
  });

  test('still rejects an empty user id before reaching the native side',
      () async {
    await expectLater(
      Setgreet.identifyUser('  ', userHash: 'a1b2c3'),
      throwsA(isA<SetgreetUserException>()),
    );
    expect(calls, isEmpty);
  });
}
