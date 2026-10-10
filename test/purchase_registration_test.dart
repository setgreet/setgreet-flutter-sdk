import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';
import 'package:setgreet/src/purchase_bridge.dart';

class _Provider extends SetgreetPurchaseProvider {
  _Provider(this.providerId);

  @override
  final String providerId;

  final List<String> calls = [];

  @override
  Future<List<SetgreetPurchaseProduct>> loadProducts(
      SetgreetPurchaseSource source) async {
    calls.add('loadProducts');
    return const [];
  }

  @override
  Future<SetgreetPurchaseResult> purchase(
      String productRef, SetgreetPurchaseSource source) async {
    calls.add('purchase');
    return SetgreetPurchaseResult(
        status: SetgreetPurchaseStatus.purchased, productRef: productRef);
  }

  @override
  Future<SetgreetRestoreResult> restorePurchases() async {
    calls.add('restorePurchases');
    return const SetgreetRestoreResult(status: SetgreetRestoreStatus.restored);
  }

  @override
  Future<SetgreetPurchaseAccessState?> accessState() async => null;
}

/// Every test here starts from a fresh bridge on an initialized SDK, so they
/// run in any order. The uninitialized case lives in its own file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const mainChannel = MethodChannel('setgreet');
  const eventChannel = MethodChannel('setgreet/events');
  const codec = StandardMethodCodec();

  final calls = <MethodCall>[];

  /// How the fake native side answers `setPurchaseProvider`; null accepts.
  Future<void> Function(MethodCall call)? onRegister;

  /// Delivers a native call to the Dart handler; null means "not implemented".
  Future<ByteData?> callFromNative(String method, [Object? arguments]) =>
      messenger.handlePlatformMessage(
        SetgreetPurchaseBridge.channel.name,
        codec.encodeMethodCall(MethodCall(method, arguments)),
        null,
      );

  List<MethodCall> registrations() =>
      calls.where((call) => call.method == 'setPurchaseProvider').toList();

  setUpAll(() async {
    messenger.setMockMethodCallHandler(mainChannel, (call) async {
      calls.add(call);
      if (call.method == 'setPurchaseProvider') await onRegister?.call(call);
      return null;
    });
    // `initialize` starts listening for flow events.
    messenger.setMockMethodCallHandler(eventChannel, (call) async => null);
    await Setgreet.initialize('app-key');
  });

  tearDownAll(() {
    messenger.setMockMethodCallHandler(mainChannel, null);
    messenger.setMockMethodCallHandler(eventChannel, null);
    SetgreetPurchaseBridge.debugReset();
  });

  setUp(() {
    calls.clear();
    onRegister = null;
    SetgreetPurchaseBridge.debugReset();
  });

  test('registers the provider id and the current offering by default',
      () async {
    await Setgreet.setPurchaseProvider(_Provider('revenuecat'));

    expect(registrations().single.arguments, {
      'providerId': 'revenuecat',
      'defaultSource': {'sourceType': 'current_offering', 'sourceId': null},
      'firstInIsolate': true,
    });
  });

  test('passes a custom default source; a second registration is not first',
      () async {
    await Setgreet.setPurchaseProvider(_Provider('revenuecat'));
    await Setgreet.setPurchaseProvider(
      _Provider('adapty'),
      defaultSource: const SetgreetPurchaseSource.placement('onboarding'),
    );

    expect(registrations().last.arguments, {
      'providerId': 'adapty',
      'defaultSource': {'sourceType': 'placement', 'sourceId': 'onboarding'},
      'firstInIsolate': false,
    });
  });

  test('of two registrations in flight, only the first claims to be first',
      () async {
    final first = Setgreet.setPurchaseProvider(_Provider('revenuecat'));
    await Setgreet.setPurchaseProvider(_Provider('adapty'));
    await first;

    expect(registrations().map((call) => call.arguments['firstInIsolate']),
        [true, false]);
  });

  test('a rejected first registration lets a concurrent one stand', () async {
    onRegister = (call) async {
      if (call.arguments['providerId'] == 'rejected') {
        throw PlatformException(code: 'PURCHASE_ERROR', message: 'rejected');
      }
    };
    final rejected = _Provider('rejected');
    final accepted = _Provider('revenuecat');

    final first = Setgreet.setPurchaseProvider(rejected);
    final second = Setgreet.setPurchaseProvider(accepted);
    await expectLater(first, throwsA(isA<SetgreetException>()));
    await second;
    await Setgreet.setPurchaseProvider(_Provider('later'));

    expect(registrations().map((call) => call.arguments['firstInIsolate']),
        [true, false, false]);
    await callFromNative('restorePurchases');
    expect(rejected.calls, isEmpty);
  });

  test('the handler answers native calls made during the registration call',
      () async {
    // Android loads the default source synchronously inside the native
    // registration, before it replies.
    ByteData? preloadReply;
    onRegister = (_) async {
      preloadReply = await callFromNative('loadProducts', {
        'source': {'sourceType': 'current_offering', 'sourceId': null},
      });
    };
    final provider = _Provider('revenuecat');

    await Setgreet.setPurchaseProvider(provider);

    expect(preloadReply, isNotNull, reason: 'answered "not implemented"');
    expect(provider.calls, ['loadProducts']);
  });

  test('an invalid provider id throws before any state changes', () async {
    for (final providerId in [
      '',
      'RevenueCat',
      '1provider',
      'revenue-cat',
      'a${'b' * 40}',
    ]) {
      await expectLater(
        Setgreet.setPurchaseProvider(_Provider(providerId)),
        throwsA(isA<SetgreetException>()
            .having((e) => e.code, 'code', 'INVALID_ARGUMENT')),
        reason: providerId,
      );
    }

    expect(registrations(), isEmpty);
    expect(await callFromNative('restorePurchases'), isNull,
        reason: 'no handler was attached');

    // The longest valid id passes, and is still the first registration.
    await Setgreet.setPurchaseProvider(_Provider('a${'b' * 39}'));
    expect(registrations().single.arguments['firstInIsolate'], isTrue);
  });

  test('a native rejection commits neither the provider nor the first flag',
      () async {
    final accepted = _Provider('revenuecat');
    final rejected = _Provider('adapty');
    onRegister = (call) async {
      if (call.arguments['providerId'] == 'adapty') {
        throw PlatformException(
          code: 'INVALID_ARGUMENT',
          message: 'Provider ID cannot be empty',
        );
      }
    };

    await expectLater(
      Setgreet.setPurchaseProvider(rejected),
      throwsA(isA<SetgreetException>()
          .having((e) => e.code, 'code', 'INVALID_ARGUMENT')
          .having((e) => e.message, 'message', 'Provider ID cannot be empty')),
    );
    expect(await callFromNative('restorePurchases'), isNull,
        reason: 'nothing was ever accepted');

    await Setgreet.setPurchaseProvider(accepted);
    expect(registrations().last.arguments['firstInIsolate'], isTrue);

    await expectLater(Setgreet.setPurchaseProvider(rejected),
        throwsA(isA<SetgreetException>()));
    await callFromNative('restorePurchases');

    expect(accepted.calls, ['restorePurchases']);
    expect(rejected.calls, isEmpty);
  });

  test('native calls reach the provider registered last', () async {
    final first = _Provider('first');
    final second = _Provider('second');
    await Setgreet.setPurchaseProvider(first);
    await Setgreet.setPurchaseProvider(second);

    expect(
      await callFromNative('loadProducts', {
        'source': {'sourceType': 'current_offering', 'sourceId': null},
      }),
      isNotNull,
    );
    expect(first.calls, isEmpty);
    expect(second.calls, ['loadProducts']);
  });
}
