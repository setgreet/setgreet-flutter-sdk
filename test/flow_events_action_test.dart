import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

/// An event as the native plugins send it on `setgreet/events`.
Map<Object?, Object?> _event(String type,
        [Map<Object?, Object?> extra = const {}]) =>
    {
      'type': type,
      'flowId': 'flow-1',
      'timestamp': 1760000000000.0,
      ...extra,
    };

/// The action types the native SDKs send, in their canonical snake_case.
const _canonicalActionTypes = [
  'next',
  'previous',
  'skip',
  'dismiss',
  'remind_later',
  'url',
  'deeplink',
  'request_notification_permission',
  'request_location_permission',
  'request_camera_permission',
  'request_tracking_permission',
  'request_microphone_permission',
  'request_photo_library_permission',
  'request_review',
  'share',
  'open_settings',
  'track_event',
  'custom',
  'purchase',
  'restore_purchases',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('custom action, track event and remind later parse', () {
    test('customAction, with nested data keyed by strings', () {
      final event = SetgreetFlowEvent.fromMap(_event('customAction', {
        'data': <Object?, Object?>{
          'screen': 'paywall',
          'count': 3,
          'enabled': true,
          'missing': null,
          'nested': <Object?, Object?>{'id': 'a'},
          'list': <Object?>[
            <Object?, Object?>{'id': 'b'},
            'c',
          ],
        },
        'screenIndex': 2,
      }));

      expect(event, isA<CustomActionEvent>());
      event as CustomActionEvent;
      expect(event.flowId, 'flow-1');
      expect(event.screenIndex, 2);
      expect(event.timestamp, 1760000000000.0);
      expect(event.data, {
        'screen': 'paywall',
        'count': 3,
        'enabled': true,
        'missing': null,
        'nested': {'id': 'a'},
        'list': [
          {'id': 'b'},
          'c',
        ],
      });
      expect(event.data!['nested'], isA<Map<String, Object?>>());
      expect((event.data!['list'] as List).first, isA<Map<String, Object?>>());
    });

    test('customAction without data has null data', () {
      final event = SetgreetFlowEvent.fromMap(
              _event('customAction', {'data': null, 'screenIndex': 0}))
          as CustomActionEvent;
      expect(event.data, isNull);

      final absent =
          SetgreetFlowEvent.fromMap(_event('customAction', {'screenIndex': 0}))
              as CustomActionEvent;
      expect(absent.data, isNull);
    });

    test('trackEvent', () {
      final event = SetgreetFlowEvent.fromMap(_event('trackEvent', {
        'eventName': 'plan_viewed',
        'properties': <Object?, Object?>{'plan': 'annual', 'price': 49.99},
        'screenIndex': 1,
      }));

      expect(event, isA<TrackEventEvent>());
      event as TrackEventEvent;
      expect(event.eventName, 'plan_viewed');
      expect(event.properties, {'plan': 'annual', 'price': 49.99});
      expect(event.screenIndex, 1);
    });

    test('trackEvent without properties has null properties', () {
      final event = SetgreetFlowEvent.fromMap(_event('trackEvent', {
        'eventName': 'plan_viewed',
        'properties': null,
        'screenIndex': 1,
      })) as TrackEventEvent;
      expect(event.properties, isNull);
    });

    test('remindLater', () {
      final event =
          SetgreetFlowEvent.fromMap(_event('remindLater', {'screenIndex': 3}));

      expect(event, isA<RemindLaterEvent>());
      expect((event as RemindLaterEvent).screenIndex, 3);
      expect(event.flowId, 'flow-1');
    });
  });

  group('actionTriggered', () {
    test('keeps every canonical action type as sent', () {
      for (final actionType in _canonicalActionTypes) {
        final event = SetgreetFlowEvent.fromMap(_event('actionTriggered', {
          'actionType': actionType,
          'actionName': null,
          'screenIndex': 0,
        })) as ActionTriggeredEvent;
        expect(event.actionType, actionType);
        expect(event.actionName, isNull);
      }
    });

    test('carries the Track Event name as actionName', () {
      final event = SetgreetFlowEvent.fromMap(_event('actionTriggered', {
        'actionType': 'track_event',
        'actionName': 'plan_viewed',
        'screenIndex': 4,
      })) as ActionTriggeredEvent;

      expect(event.actionType, 'track_event');
      expect(event.actionName, 'plan_viewed');
      expect(event.screenIndex, 4);
    });
  });

  group('flowError', () {
    test('maps every error type the native SDKs send', () {
      for (final entry in {
        'network': FlowErrorType.network,
        'parse': FlowErrorType.parse,
        'display': FlowErrorType.display,
        'unknown': FlowErrorType.unknown,
      }.entries) {
        final event = SetgreetFlowEvent.fromMap(_event('flowError', {
          'errorType': entry.key,
          'message': 'boom',
        })) as FlowErrorEvent;
        expect(event.errorType, entry.value);
        expect(event.message, 'boom');
      }
    });

    test('an error type from a newer native SDK is unknown', () {
      final event = SetgreetFlowEvent.fromMap(_event('flowError', {
        'errorType': 'timeout',
        'message': 'slow',
      })) as FlowErrorEvent;
      expect(event.errorType, FlowErrorType.unknown);
    });
  });

  test('each event reaches its own callback', () {
    final received = <String>[];
    final callbacks = SetgreetFlowCallbacks()
      ..onActionTriggered((e) => received.add('action ${e.actionType}'))
      ..onError((e) => received.add('error ${e.errorType.name}'))
      ..onCustomAction((e) => received.add('custom ${e.data}'))
      ..onTrackEvent((e) => received.add('track ${e.eventName}'))
      ..onRemindLater((e) => received.add('remind ${e.screenIndex}'))
      ..onFlowDismissed((_) => received.add('unexpected'));

    for (final map in [
      _event('actionTriggered', {
        'actionType': 'remind_later',
        'actionName': null,
        'screenIndex': 1,
      }),
      _event('flowError', {'errorType': 'network', 'message': 'offline'}),
      _event('customAction', {
        'data': <Object?, Object?>{'k': 'v'},
        'screenIndex': 1,
      }),
      _event('trackEvent', {
        'eventName': 'plan_viewed',
        'properties': null,
        'screenIndex': 1,
      }),
      _event('remindLater', {'screenIndex': 1}),
    ]) {
      callbacks.dispatchEvent(SetgreetFlowEvent.fromMap(map));
    }

    expect(received, [
      'action remind_later',
      'error network',
      'custom {k: v}',
      'track plan_viewed',
      'remind 1',
    ]);
  });

  test('an unset callback ignores its event', () {
    final callbacks = SetgreetFlowCallbacks();
    expect(
      () => callbacks.dispatchEvent(
          SetgreetFlowEvent.fromMap(_event('remindLater', {'screenIndex': 0}))),
      returnsNormally,
    );
  });

  test('the new events arrive through Setgreet.flowEvents', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const events = EventChannel('setgreet/events');
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (arguments, sink) {
        sink.success(_event('customAction', {
          'data': <Object?, Object?>{'k': 'v'},
          'screenIndex': 0,
        }));
        sink.success(_event('trackEvent', {
          'eventName': 'plan_viewed',
          'properties': <Object?, Object?>{'plan': 'annual'},
          'screenIndex': 0,
        }));
        sink.success(_event('remindLater', {'screenIndex': 0}));
        sink.endOfStream();
      }),
    );
    addTearDown(() => messenger.setMockStreamHandler(events, null));

    final received = await Setgreet.flowEvents.take(3).toList();

    expect((received[0] as CustomActionEvent).data, {'k': 'v'});
    expect((received[1] as TrackEventEvent).properties, {'plan': 'annual'});
    expect(received[2], isA<RemindLaterEvent>());
  });
}
