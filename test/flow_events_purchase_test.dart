import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

/// The fields every purchase event carries, as the native plugins send them.
Map<String, Object?> _event(String type,
        [Map<String, Object?> extra = const {}]) =>
    {
      'type': type,
      'flowId': 'flow-1',
      'screenId': 'screen-1',
      'componentId': 'buy-button',
      'provider': 'revenuecat',
      'timestamp': 1760000000000.0,
      ...extra,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('purchase events parse from the native maps', () {
    test('purchaseCompleted', () {
      final event = SetgreetFlowEvent.fromMap(_event('purchaseCompleted', {
        'productRef': r'$rc_annual',
        'accessRefs': ['premium'],
      }));

      expect(event, isA<PurchaseCompletedEvent>());
      event as PurchaseCompletedEvent;
      expect(event.flowId, 'flow-1');
      expect(event.screenId, 'screen-1');
      expect(event.componentId, 'buy-button');
      expect(event.productRef, r'$rc_annual');
      expect(event.provider, 'revenuecat');
      expect(event.accessRefs, ['premium']);
      expect(event.timestamp, 1760000000000.0);
    });

    test('purchaseCompleted without accessRefs has none', () {
      final event = SetgreetFlowEvent.fromMap(
              _event('purchaseCompleted', {'productRef': r'$rc_annual'}))
          as PurchaseCompletedEvent;
      expect(event.accessRefs, isEmpty);
    });

    test('purchaseCancelled', () {
      final event = SetgreetFlowEvent.fromMap(
          _event('purchaseCancelled', {'productRef': r'$rc_monthly'}));

      expect(event, isA<PurchaseCancelledEvent>());
      expect((event as PurchaseCancelledEvent).productRef, r'$rc_monthly');
      expect(event.componentId, 'buy-button');
    });

    test('purchaseFailed carries the normalized error', () {
      final event = SetgreetFlowEvent.fromMap(_event('purchaseFailed', {
        'productRef': r'$rc_annual',
        'error': {
          'code': 'network_error',
          'providerCode': 'NetworkError',
          'message': 'offline',
        },
      })) as PurchaseFailedEvent;

      expect(event.productRef, r'$rc_annual');
      expect(event.error.code, SetgreetPurchaseErrorCode.networkError);
      expect(event.error.providerCode, 'NetworkError');
      expect(event.error.message, 'offline');
    });

    test('an unrecognized or missing error code is unknown', () {
      final unrecognized = SetgreetFlowEvent.fromMap(_event('purchaseFailed', {
        'productRef': 'x',
        'error': {
          'code': 'brand_new_code',
          'providerCode': null,
          'message': null
        },
      })) as PurchaseFailedEvent;
      expect(unrecognized.error.code, SetgreetPurchaseErrorCode.unknown);
      expect(unrecognized.error.providerCode, isNull);

      final missing = SetgreetFlowEvent.fromMap(
          _event('purchaseFailed', {'productRef': 'x'})) as PurchaseFailedEvent;
      expect(missing.error.code, SetgreetPurchaseErrorCode.unknown);
    });

    test('purchasePending', () {
      final event = SetgreetFlowEvent.fromMap(
          _event('purchasePending', {'productRef': r'$rc_annual'}));

      expect(event, isA<PurchasePendingEvent>());
      expect((event as PurchasePendingEvent).productRef, r'$rc_annual');
    });

    test('restoreCompleted, with either status', () {
      final restored = SetgreetFlowEvent.fromMap(_event('restoreCompleted', {
        'status': 'restored',
        'accessRefs': ['premium'],
      })) as RestoreCompletedEvent;
      expect(restored.status, SetgreetRestoreStatus.restored);
      expect(restored.accessRefs, ['premium']);
      expect(restored.componentId, 'buy-button');

      final nothing = SetgreetFlowEvent.fromMap(_event('restoreCompleted', {
        'status': 'nothingToRestore',
        'accessRefs': <String>[],
      })) as RestoreCompletedEvent;
      expect(nothing.status, SetgreetRestoreStatus.nothingToRestore);
      expect(nothing.accessRefs, isEmpty);
    });

    test('restoreCompleted with an unknown status is malformed', () {
      expect(
        () => SetgreetFlowEvent.fromMap(
            _event('restoreCompleted', {'status': 'partial'})),
        throwsArgumentError,
      );
    });

    test('restoreFailed carries the normalized error', () {
      final event = SetgreetFlowEvent.fromMap(_event('restoreFailed', {
        'error': {
          'code': 'restore_failed',
          'providerCode': 'StoreProblemError',
          'message': 'store down',
        },
      })) as RestoreFailedEvent;

      expect(event.provider, 'revenuecat');
      expect(event.error.code, SetgreetPurchaseErrorCode.restoreFailed);
      expect(event.error.providerCode, 'StoreProblemError');
    });
  });

  test('each purchase event reaches its own callback', () {
    final received = <String>[];
    final callbacks = SetgreetFlowCallbacks()
      ..onPurchaseCompleted((e) => received.add('completed ${e.productRef}'))
      ..onPurchaseCancelled((e) => received.add('cancelled ${e.productRef}'))
      ..onPurchaseFailed((e) => received.add('failed ${e.error.code.rawValue}'))
      ..onPurchasePending((e) => received.add('pending ${e.productRef}'))
      ..onRestoreCompleted((e) => received.add('restored ${e.status.rawValue}'))
      ..onRestoreFailed(
          (e) => received.add('restoreFailed ${e.error.code.rawValue}'))
      ..onFlowStarted((_) => received.add('unexpected'));

    for (final map in [
      _event('purchaseCompleted', {'productRef': 'a'}),
      _event('purchaseCancelled', {'productRef': 'b'}),
      _event('purchaseFailed', {
        'productRef': 'c',
        'error': {'code': 'purchase_failed'},
      }),
      _event('purchasePending', {'productRef': 'd'}),
      _event('restoreCompleted', {'status': 'nothingToRestore'}),
      _event('restoreFailed', {
        'error': {'code': 'restore_failed'},
      }),
    ]) {
      callbacks.dispatchEvent(SetgreetFlowEvent.fromMap(map));
    }

    expect(received, [
      'completed a',
      'cancelled b',
      'failed purchase_failed',
      'pending d',
      'restored nothingToRestore',
      'restoreFailed restore_failed',
    ]);
  });

  test('purchase events arrive through Setgreet.flowEvents', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const events = EventChannel('setgreet/events');
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (arguments, sink) {
        sink.success(_event('purchaseCompleted', {
          'productRef': r'$rc_annual',
          'accessRefs': ['premium'],
        }));
        sink.success(_event('restoreFailed', {
          'error': {
            'code': 'network_error',
            'providerCode': null,
            'message': null
          },
        }));
        sink.endOfStream();
      }),
    );
    addTearDown(() => messenger.setMockStreamHandler(events, null));

    final received = await Setgreet.flowEvents.take(2).toList();

    expect(received, hasLength(2));
    expect((received[0] as PurchaseCompletedEvent).accessRefs, ['premium']);
    expect((received[1] as RestoreFailedEvent).error.code,
        SetgreetPurchaseErrorCode.networkError);
  });
}
