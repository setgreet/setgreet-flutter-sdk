import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';
import 'package:setgreet/src/purchase_bridge.dart';

class _Provider extends SetgreetPurchaseProvider {
  @override
  String get providerId => 'revenuecat';

  @override
  Future<List<SetgreetPurchaseProduct>> loadProducts(
          SetgreetPurchaseSource source) async =>
      const [];

  @override
  Future<SetgreetPurchaseResult> purchase(
          String productRef, SetgreetPurchaseSource source) async =>
      SetgreetPurchaseResult(
          status: SetgreetPurchaseStatus.purchased, productRef: productRef);

  @override
  Future<SetgreetRestoreResult> restorePurchases() async =>
      const SetgreetRestoreResult(status: SetgreetRestoreStatus.restored);

  @override
  Future<SetgreetPurchaseAccessState?> accessState() async => null;
}

// Its own file: the SDK's initialized state is static and cannot be reset,
// and this test needs an SDK that was never initialized.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const mainChannel = MethodChannel('setgreet');

  test('registering before initialize throws and touches nothing', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(mainChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(mainChannel, null));

    await expectLater(
      Setgreet.setPurchaseProvider(_Provider()),
      throwsA(isA<SetgreetInitializationException>()),
    );

    expect(calls, isEmpty);
    expect(SetgreetPurchaseBridge.isFirstRegistration, isTrue);
    final reply = await messenger.handlePlatformMessage(
      SetgreetPurchaseBridge.channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('restorePurchases')),
      null,
    );
    expect(reply, isNull, reason: 'no handler was attached');
  });
}
