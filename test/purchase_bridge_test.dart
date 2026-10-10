import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';
import 'package:setgreet/src/purchase_bridge.dart';

/// A provider whose answers each test sets, recording what it was called with.
class _ScriptedProvider extends SetgreetPurchaseProvider {
  _ScriptedProvider({this.id = 'scripted'});

  final String id;

  Future<List<SetgreetPurchaseProduct>> Function(SetgreetPurchaseSource)
      onLoadProducts = (_) async => const [];
  Future<SetgreetPurchaseResult> Function(String, SetgreetPurchaseSource)
      onPurchase = (ref, _) async => SetgreetPurchaseResult(
            status: SetgreetPurchaseStatus.purchased,
            productRef: ref,
          );
  Future<SetgreetRestoreResult> Function() onRestore = () async =>
      const SetgreetRestoreResult(status: SetgreetRestoreStatus.restored);
  Future<SetgreetPurchaseAccessState?> Function() onAccessState =
      () async => null;
  void Function(SetgreetPaywallImpressionContext) onImpression = (_) {};
  void Function(Map<String, String>) onAttributes = (_) {};
  Future<void> Function(String) onIdentify = (_) async {};
  Future<void> Function() onReset = () async {};

  final List<String> calls = [];
  SetgreetPurchaseSource? lastSource;
  String? lastProductRef;

  @override
  String get providerId => id;

  @override
  Future<List<SetgreetPurchaseProduct>> loadProducts(
      SetgreetPurchaseSource source) {
    calls.add('loadProducts');
    lastSource = source;
    return onLoadProducts(source);
  }

  @override
  Future<SetgreetPurchaseResult> purchase(
      String productRef, SetgreetPurchaseSource source) {
    calls.add('purchase');
    lastProductRef = productRef;
    lastSource = source;
    return onPurchase(productRef, source);
  }

  @override
  Future<SetgreetRestoreResult> restorePurchases() {
    calls.add('restorePurchases');
    return onRestore();
  }

  @override
  Future<SetgreetPurchaseAccessState?> accessState() {
    calls.add('accessState');
    return onAccessState();
  }

  @override
  void trackPaywallImpression(SetgreetPaywallImpressionContext context) {
    calls.add('trackPaywallImpression');
    onImpression(context);
  }

  @override
  void setAttributes(Map<String, String> attributes) {
    calls.add('setAttributes');
    onAttributes(attributes);
  }

  @override
  Future<void> identify(String userId) {
    calls.add('identify');
    return onIdentify(userId);
  }

  @override
  Future<void> reset() {
    calls.add('reset');
    return onReset();
  }
}

/// Implements the required methods only: the optional ones keep the base
/// class's no-op bodies.
class _MinimalProvider extends SetgreetPurchaseProvider {
  @override
  String get providerId => 'minimal';

  @override
  Future<List<SetgreetPurchaseProduct>> loadProducts(
          SetgreetPurchaseSource source) async =>
      const [];

  @override
  Future<SetgreetPurchaseResult> purchase(
          String productRef, SetgreetPurchaseSource source) async =>
      SetgreetPurchaseResult(
          status: SetgreetPurchaseStatus.cancelled, productRef: productRef);

  @override
  Future<SetgreetRestoreResult> restorePurchases() async =>
      const SetgreetRestoreResult(
          status: SetgreetRestoreStatus.nothingToRestore);

  @override
  Future<SetgreetPurchaseAccessState?> accessState() async => null;
}

const _annual = SetgreetPurchaseProduct(
  ref: r'$rc_annual',
  storeProductId: 'com.app.premium.annual',
  title: 'Premium Annual',
  description: 'Full access, billed yearly',
  localizedPrice: r'$49.99',
  priceAmount: 49.99,
  currencyCode: 'USD',
  period:
      SetgreetPurchasePeriod(unit: SetgreetPurchasePeriodUnit.year, count: 1),
  introOffer: SetgreetPurchaseIntroOffer(
    type: SetgreetPurchaseIntroOffer.trialType,
    localizedPrice: r'$0.00',
    periodText: '7 days',
    eligible: true,
  ),
);

const _lifetime = SetgreetPurchaseProduct(
  ref: 'lifetime',
  storeProductId: 'com.app.lifetime',
  localizedPrice: r'$99.00',
  priceAmount: 99,
  currencyCode: 'USD',
);

/// A registration the native side accepted.
void _register(SetgreetPurchaseProvider provider) {
  SetgreetPurchaseBridge.commit(SetgreetPurchaseBridge.begin(provider));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  /// Delivers [method] to the Dart handler the way the native proxy does and
  /// returns the raw reply: null means "not implemented".
  Future<ByteData?> sendFromNative(String method, [Object? arguments]) =>
      messenger.handlePlatformMessage(
        SetgreetPurchaseBridge.channel.name,
        codec.encodeMethodCall(MethodCall(method, arguments)),
        null,
      );

  /// The decoded reply. Throws the [PlatformException] of an error reply.
  Future<Object?> invokeFromNative(String method, [Object? arguments]) async {
    final reply = await sendFromNative(method, arguments);
    expect(reply, isNotNull, reason: '$method was answered "not implemented"');
    return codec.decodeEnvelope(reply!);
  }

  const offeringSource = {'sourceType': 'offering', 'sourceId': 'discount'};

  late _ScriptedProvider provider;

  setUp(() {
    SetgreetPurchaseBridge.debugReset();
    provider = _ScriptedProvider();
    _register(provider);
  });

  tearDown(SetgreetPurchaseBridge.debugReset);

  group('loadProducts', () {
    test('passes the source and returns every product field', () async {
      provider.onLoadProducts = (_) async => [_annual, _lifetime];

      final reply = await invokeFromNative('loadProducts', {
        'source': offeringSource,
      }) as List<Object?>;

      expect(provider.lastSource,
          const SetgreetPurchaseSource.offering('discount'));
      expect(reply, [
        {
          'ref': r'$rc_annual',
          'storeProductId': 'com.app.premium.annual',
          'title': 'Premium Annual',
          'description': 'Full access, billed yearly',
          'localizedPrice': r'$49.99',
          'priceAmount': 49.99,
          'currencyCode': 'USD',
          'period': {'unit': 'year', 'count': 1},
          'introOffer': {
            'type': 'trial',
            'localizedPrice': r'$0.00',
            'periodText': '7 days',
            'eligible': true,
          },
        },
        {
          'ref': 'lifetime',
          'storeProductId': 'com.app.lifetime',
          'title': null,
          'description': null,
          'localizedPrice': r'$99.00',
          'priceAmount': 99.0,
          'currencyCode': 'USD',
          'period': null,
          'introOffer': null,
        },
      ]);
    });

    test('priceAmount crosses as a double, even for a whole price', () async {
      provider.onLoadProducts = (_) async => [_annual, _lifetime];

      final reply = await invokeFromNative('loadProducts', {
        'source': offeringSource,
      }) as List<Object?>;

      for (final product in reply.cast<Map<Object?, Object?>>()) {
        expect(product['priceAmount'], isA<double>());
      }
    });

    test('a missing source is the current offering', () async {
      await invokeFromNative('loadProducts', {});
      expect(
          provider.lastSource, const SetgreetPurchaseSource.currentOffering());
      expect(provider.lastSource!.sourceId, isNull);
    });

    test('a thrown SetgreetPurchaseError becomes an error reply with its code',
        () async {
      provider.onLoadProducts = (_) async => throw const SetgreetPurchaseError(
            code: SetgreetPurchaseErrorCode.networkError,
            providerCode: 'NetworkError',
            message: 'offline',
          );

      await expectLater(
        invokeFromNative('loadProducts', {'source': offeringSource}),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'network_error')
            .having((e) => e.message, 'message', 'offline')
            .having(
                (e) => e.details, 'details', {'providerCode': 'NetworkError'})),
      );
    });

    test('any other error becomes an `unknown` error reply', () async {
      provider.onLoadProducts = (_) async => throw StateError('boom');

      await expectLater(
        invokeFromNative('loadProducts', {'source': offeringSource}),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'unknown')
            .having((e) => e.message, 'message', contains('boom'))),
      );
    });
  });

  group('purchase', () {
    test('passes the ref with its source and returns the result', () async {
      provider.onPurchase = (ref, _) async => SetgreetPurchaseResult(
            status: SetgreetPurchaseStatus.purchased,
            productRef: ref,
            accessRefs: const ['premium'],
          );

      final reply = await invokeFromNative('purchase', {
        'productRef': r'$rc_annual',
        'source': offeringSource,
      });

      expect(provider.lastProductRef, r'$rc_annual');
      expect(provider.lastSource,
          const SetgreetPurchaseSource.offering('discount'));
      expect(reply, {
        'status': 'purchased',
        'productRef': r'$rc_annual',
        'accessRefs': ['premium'],
        'error': null,
      });
    });

    test('a pending result keeps its error', () async {
      provider.onPurchase = (ref, _) async => SetgreetPurchaseResult(
            status: SetgreetPurchaseStatus.pending,
            productRef: ref,
            error: const SetgreetPurchaseError(
              code: SetgreetPurchaseErrorCode.purchasePending,
              providerCode: 'paymentPendingError',
            ),
          );

      final reply = await invokeFromNative('purchase', {
        'productRef': r'$rc_monthly',
        'source': offeringSource,
      });

      expect(reply, {
        'status': 'pending',
        'productRef': r'$rc_monthly',
        'accessRefs': <String>[],
        'error': {
          'code': 'purchase_pending',
          'providerCode': 'paymentPendingError',
          'message': null,
        },
      });
    });

    test('a thrown SetgreetPurchaseError is `failed` with its code', () async {
      provider.onPurchase = (_, __) async => throw const SetgreetPurchaseError(
            code: SetgreetPurchaseErrorCode.productNotFound,
            message: 'no such package',
          );

      final reply = await invokeFromNative('purchase', {
        'productRef': r'$rc_annual',
        'source': offeringSource,
      });

      expect(reply, {
        'status': 'failed',
        'productRef': r'$rc_annual',
        'accessRefs': <String>[],
        'error': {
          'code': 'product_not_found',
          'providerCode': null,
          'message': 'no such package',
        },
      });
    });

    test('any other thrown error is `failed` with `unknown`', () async {
      provider.onPurchase = (_, __) => throw StateError('sheet crashed');

      final reply = await invokeFromNative('purchase', {
        'productRef': r'$rc_annual',
        'source': offeringSource,
      }) as Map<Object?, Object?>;

      expect(reply['status'], 'failed');
      expect(reply['productRef'], r'$rc_annual');
      final error = reply['error'] as Map<Object?, Object?>;
      expect(error['code'], 'unknown');
      expect(error['message'], contains('sheet crashed'));
    });
  });

  group('restorePurchases', () {
    test('returns the status and access refs', () async {
      provider.onRestore = () async => const SetgreetRestoreResult(
            status: SetgreetRestoreStatus.restored,
            accessRefs: ['premium'],
          );

      expect(await invokeFromNative('restorePurchases'), {
        'status': 'restored',
        'accessRefs': ['premium'],
        'error': null,
      });
    });

    test('nothingToRestore keeps its camelCase wire value', () async {
      provider.onRestore = () async => const SetgreetRestoreResult(
          status: SetgreetRestoreStatus.nothingToRestore);

      final reply =
          await invokeFromNative('restorePurchases') as Map<Object?, Object?>;
      expect(reply['status'], 'nothingToRestore');
    });

    test('a thrown error is `failed`, keeping a SetgreetPurchaseError code',
        () async {
      provider.onRestore = () async => throw const SetgreetPurchaseError(
          code: SetgreetPurchaseErrorCode.restoreFailed);
      var reply =
          await invokeFromNative('restorePurchases') as Map<Object?, Object?>;
      expect(reply['status'], 'failed');
      expect((reply['error'] as Map)['code'], 'restore_failed');

      provider.onRestore = () async => throw Exception('store down');
      reply =
          await invokeFromNative('restorePurchases') as Map<Object?, Object?>;
      expect(reply['status'], 'failed');
      expect((reply['error'] as Map)['code'], 'unknown');
    });
  });

  group('accessState', () {
    test('returns active and the access refs', () async {
      provider.onAccessState = () async => const SetgreetPurchaseAccessState(
            active: true,
            accessRefs: ['premium', 'pro'],
          );

      expect(await invokeFromNative('accessState'), {
        'active': true,
        'accessRefs': ['premium', 'pro'],
      });
    });

    test('null stays null: the provider cannot say', () async {
      provider.onAccessState = () async => null;
      expect(await invokeFromNative('accessState'), isNull);
    });

    test('a thrown error is null, not an error reply', () async {
      provider.onAccessState = () async => throw StateError('no customer info');
      expect(await invokeFromNative('accessState'), isNull);
    });
  });

  group('fire-and-forget and identity', () {
    test('trackPaywallImpression receives the full context', () async {
      SetgreetPaywallImpressionContext? received;
      provider.onImpression = (context) => received = context;

      expect(
        await invokeFromNative('trackPaywallImpression', {
          'flowId': 'flow-1',
          'screenId': 'screen-1',
          'source': offeringSource,
          'productRefs': [r'$rc_annual', r'$rc_monthly'],
        }),
        isNull,
      );

      expect(received!.flowId, 'flow-1');
      expect(received!.screenId, 'screen-1');
      expect(
          received!.source, const SetgreetPurchaseSource.offering('discount'));
      expect(received!.productRefs, [r'$rc_annual', r'$rc_monthly']);
    });

    test('setAttributes receives a String map', () async {
      Map<String, String>? received;
      provider.onAttributes = (attributes) => received = attributes;

      await invokeFromNative('setAttributes', {
        'attributes': {
          'setgreet_flow': 'flow-1',
          'setgreet_screen': 'screen-1'
        },
      });

      expect(
          received, {'setgreet_flow': 'flow-1', 'setgreet_screen': 'screen-1'});
    });

    test('identify and reset reach the provider', () async {
      String? identified;
      provider.onIdentify = (userId) async => identified = userId;

      expect(await invokeFromNative('identify', {'userId': 'user-42'}), isNull);
      expect(await invokeFromNative('reset'), isNull);

      expect(identified, 'user-42');
      expect(provider.calls, ['identify', 'reset']);
    });

    test('a provider error never reaches the native side', () async {
      provider.onImpression = (_) => throw StateError('analytics down');
      provider.onAttributes = (_) => throw StateError('attributes down');
      provider.onIdentify = (_) async => throw StateError('logIn failed');
      provider.onReset = () async => throw StateError('logOut failed');

      expect(
          await invokeFromNative('trackPaywallImpression', {
            'flowId': 'f',
            'screenId': 's',
            'source': offeringSource,
            'productRefs': <String>[],
          }),
          isNull);
      expect(
          await invokeFromNative('setAttributes', {'attributes': {}}), isNull);
      expect(await invokeFromNative('identify', {'userId': 'u'}), isNull);
      expect(await invokeFromNative('reset'), isNull);
    });

    test('the optional methods default to no-ops', () async {
      _register(_MinimalProvider());

      expect(
          await invokeFromNative('trackPaywallImpression', {
            'flowId': 'f',
            'screenId': 's',
            'source': offeringSource,
            'productRefs': [r'$rc_annual'],
          }),
          isNull);
      expect(
        await invokeFromNative('setAttributes', {
          'attributes': {'setgreet_flow': 'f'},
        }),
        isNull,
      );
      expect(await invokeFromNative('identify', {'userId': 'u'}), isNull);
      expect(await invokeFromNative('reset'), isNull);
    });
  });

  group('no usable provider', () {
    test('an unknown method is answered "not implemented"', () async {
      expect(
          await sendFromNative('refundPurchase', {'productRef': 'x'}), isNull);
      expect(provider.calls, isEmpty);
    });

    test('with no provider registered, every call is "not implemented"',
        () async {
      SetgreetPurchaseBridge.debugReset();

      for (final method in [
        'loadProducts',
        'purchase',
        'restorePurchases',
        'accessState',
        'identify',
        'reset',
      ]) {
        expect(await sendFromNative(method, {}), isNull, reason: method);
      }
    });

    test('a later registration replaces the provider', () async {
      final replacement = _ScriptedProvider(id: 'replacement');
      _register(replacement);

      await invokeFromNative('restorePurchases');

      expect(provider.calls, isEmpty);
      expect(replacement.calls, ['restorePurchases']);
    });
  });

  group('registration state', () {
    test('a provider in registration answers before it is committed', () async {
      final next = _ScriptedProvider(id: 'next');
      SetgreetPurchaseBridge.begin(next);

      await invokeFromNative('restorePurchases');

      expect(next.calls, ['restorePurchases']);
      expect(provider.calls, isEmpty);
    });

    test('an abandoned registration hands the calls back', () async {
      final rejected = _ScriptedProvider(id: 'rejected');
      SetgreetPurchaseBridge.abandon(SetgreetPurchaseBridge.begin(rejected));

      await invokeFromNative('restorePurchases');

      expect(rejected.calls, isEmpty);
      expect(provider.calls, ['restorePurchases']);
    });

    test('only a committed registration ends the first one in the isolate', () {
      SetgreetPurchaseBridge.debugReset();
      final first = _MinimalProvider();

      expect(SetgreetPurchaseBridge.isFirstRegistration, isTrue);
      final rejected = SetgreetPurchaseBridge.begin(first);
      expect(rejected.firstInIsolate, isTrue);
      SetgreetPurchaseBridge.abandon(rejected);
      expect(SetgreetPurchaseBridge.isFirstRegistration, isTrue);

      final accepted = SetgreetPurchaseBridge.begin(first);
      expect(accepted.firstInIsolate, isTrue);
      SetgreetPurchaseBridge.commit(accepted);
      expect(SetgreetPurchaseBridge.isFirstRegistration, isFalse);
      expect(SetgreetPurchaseBridge.begin(first).firstInIsolate, isFalse);
    });

    test('only the first registration in flight claims to be the first', () {
      SetgreetPurchaseBridge.debugReset();
      final provider = _MinimalProvider();

      final first = SetgreetPurchaseBridge.begin(provider);
      final second = SetgreetPurchaseBridge.begin(provider);
      expect(first.firstInIsolate, isTrue);
      expect(second.firstInIsolate, isFalse);

      // The claimant was rejected: the next registration may claim again,
      // until one is accepted.
      SetgreetPurchaseBridge.abandon(first);
      final third = SetgreetPurchaseBridge.begin(provider);
      expect(third.firstInIsolate, isTrue);
      SetgreetPurchaseBridge.commit(second);
      SetgreetPurchaseBridge.commit(third);
      expect(SetgreetPurchaseBridge.begin(provider).firstInIsolate, isFalse);
    });
  });
}
