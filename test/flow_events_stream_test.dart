import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

/// A purchase event as the native plugins send it on `setgreet/events`.
Map<String, Object?> _purchaseCompleted(String productRef) => {
      'type': 'purchaseCompleted',
      'flowId': 'flow-1',
      'screenId': 'screen-1',
      'componentId': 'buy',
      'productRef': productRef,
      'provider': 'revenuecat',
      'accessRefs': ['premium'],
      'timestamp': 1760000000000.0,
    };

String _productRef(SetgreetFlowEvent event) =>
    (event as PurchaseCompletedEvent).productRef;

/// Lets the platform message and the stream deliveries run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

// `setgreet/events` keeps one Dart message handler per channel name: the
// callbacks set with `setFlowCallbacks` and every `Setgreet.flowEvents`
// listener must share one platform subscription. The counts below hold
// whatever order the tests run in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const events = EventChannel('setgreet/events');

  var platformListens = 0;
  var platformCancels = 0;
  MockStreamHandlerEventSink? sink;
  final fromCallbacks = <String>[];

  Future<void> emit(String productRef) async {
    sink!.success(_purchaseCompleted(productRef));
    await _settle();
  }

  setUpAll(() async {
    messenger.setMockMethodCallHandler(
        const MethodChannel('setgreet'), (call) async => null);
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, eventSink) {
          platformListens++;
          sink = eventSink;
        },
        onCancel: (arguments) => platformCancels++,
      ),
    );

    await Setgreet.initialize('app-key');
    Setgreet.setFlowCallbacks(SetgreetFlowCallbacks()
      ..onPurchaseCompleted((event) => fromCallbacks.add(event.productRef)));
    await _settle();
  });

  tearDownAll(() {
    messenger.setMockMethodCallHandler(const MethodChannel('setgreet'), null);
    Setgreet.clearFlowCallbacks();
  });

  setUp(fromCallbacks.clear);

  test('callbacks keep firing while a flowEvents listener is active', () async {
    final streamed = <String>[];
    final subscription =
        Setgreet.flowEvents.listen((event) => streamed.add(_productRef(event)));
    await _settle();

    await emit('a');

    expect(fromCallbacks, ['a']);
    expect(streamed, ['a']);
    await subscription.cancel();
  });

  test('cancelling a flowEvents listener leaves the callbacks running',
      () async {
    final subscription = Setgreet.flowEvents.listen((_) {});
    await _settle();
    await subscription.cancel();
    await _settle();

    await emit('b');

    expect(fromCallbacks, ['b']);
    expect(platformCancels, 0, reason: 'the platform subscription stays');
  });

  test('two flowEvents listeners and the callbacks all receive the events',
      () async {
    final first = <String>[];
    final second = <String>[];
    final a =
        Setgreet.flowEvents.listen((event) => first.add(_productRef(event)));
    final b =
        Setgreet.flowEvents.listen((event) => second.add(_productRef(event)));
    await _settle();

    await emit('c');
    await a.cancel();
    await emit('d');

    expect(fromCallbacks, ['c', 'd']);
    expect(first, ['c']);
    expect(second, ['c', 'd']);
    await b.cancel();
  });

  test('every flowEvents read shares the one platform subscription', () async {
    final subscriptions = [
      for (var i = 0; i < 3; i++) Setgreet.flowEvents.listen((_) {}),
    ];
    await _settle();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await _settle();

    expect(platformListens, 1);
    expect(platformCancels, 0);
  });
}
