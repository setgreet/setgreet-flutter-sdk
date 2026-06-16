import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'config.dart';
import 'exceptions.dart';
import 'flow_events.dart';
import 'flow_callbacks.dart';
import 'theme_extractor.dart';
import 'theme_sync_api.dart';

/// Main Setgreet SDK class
class Setgreet {
  static const MethodChannel _channel = MethodChannel('setgreet');
  static const EventChannel _eventChannel = EventChannel('setgreet/events');

  /// Default Setgreet API base URL (matches the native SDKs' production host).
  static const String _defaultApiUrl = 'https://api.setgreet.com/api/v1';

  static bool _initialized = false;
  static SetgreetFlowCallbacks? _callbacks;
  static StreamSubscription? _eventSubscription;

  static String? _appKey;
  static String _apiUrl = _defaultApiUrl;

  /// @visibleForTesting — the API client used by [syncTheme]. Swappable so tests
  /// can assert the request without real network I/O.
  static ThemeSyncApi themeSyncApi = const ThemeSyncApi();

  /// Initialize the Setgreet SDK with your app key
  ///
  /// [appKey] - Your Setgreet application key from the dashboard
  /// [config] - Optional configuration for the SDK
  ///
  /// Throws [SetgreetInitializationException] if initialization fails
  static Future<void> initialize(String appKey, {SetgreetConfig? config}) async {
    try {
      if (appKey.trim().isEmpty) {
        throw SetgreetInitializationException('App key cannot be empty');
      }

      final resolvedConfig = config ?? const SetgreetConfig();
      final configMap = resolvedConfig.toMap();
      configMap['appKey'] = appKey;

      await _channel.invokeMethod('initialize', configMap);
      _initialized = true;
      _appKey = appKey;
      _apiUrl = resolvedConfig.apiUrl ?? _defaultApiUrl;

      // Start listening for flow events
      _startEventListener();
    } on PlatformException catch (e) {
      throw SetgreetInitializationException(
        e.message ?? 'Failed to initialize Setgreet SDK',
        code: e.code,
      );
    }
  }

  /// Start listening for flow events from native
  static void _startEventListener() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel
        .receiveBroadcastStream()
        .listen(_handleEvent, onError: _handleEventError);
  }

  /// Handle incoming flow events
  static void _handleEvent(dynamic event) {
    if (event == null || _callbacks == null) return;

    try {
      final map = Map<dynamic, dynamic>.from(event as Map);
      final flowEvent = SetgreetFlowEvent.fromMap(map);
      _callbacks?.dispatchEvent(flowEvent);
    } catch (e) {
      // Silently ignore malformed events
    }
  }

  /// Handle event stream errors
  static void _handleEventError(dynamic error) {
    // Silently ignore stream errors
  }

  /// Identify a user with optional attributes, operation, and locale
  ///
  /// [userId] - Unique identifier for the user
  /// [attributes] - Optional user attributes as key-value pairs
  /// [operation] - Optional operation type ('create' or 'update', defaults to 'create')
  /// [locale] - Optional user locale (e.g., "en-US"). If not provided, uses device's default locale
  ///
  /// Throws [SetgreetUserException] if user identification fails
  static Future<void> identifyUser(
    String userId, {
    Map<String, dynamic>? attributes,
    String? operation,
    String? locale,
  }) async {
    try {
      _ensureInitialized();

      if (userId.trim().isEmpty) {
        throw SetgreetUserException('User ID cannot be empty');
      }

      await _channel.invokeMethod('identifyUser', {
        'userId': userId,
        'attributes': attributes ?? {},
        'operation': operation ?? 'create',
        'locale': locale,
      });
    } on PlatformException catch (e) {
      throw SetgreetUserException(
        e.message ?? 'Failed to identify user',
        code: e.code,
      );
    }
  }

  /// Reset the current user session
  ///
  /// Throws [SetgreetUserException] if reset fails
  static Future<void> resetUser() async {
    try {
      _ensureInitialized();
      await _channel.invokeMethod('resetUser');
    } on PlatformException catch (e) {
      throw SetgreetUserException(
        e.message ?? 'Failed to reset user',
        code: e.code,
      );
    }
  }

  /// Track a custom event
  ///
  /// [eventName] - Name of the event to track
  /// [properties] - Optional event properties as key-value pairs
  ///
  /// Throws [SetgreetTrackingException] if event tracking fails
  static Future<void> trackEvent(
    String eventName, {
    Map<String, dynamic>? properties,
  }) async {
    try {
      _ensureInitialized();

      if (eventName.trim().isEmpty) {
        throw SetgreetTrackingException('Event name cannot be empty');
      }

      await _channel.invokeMethod('trackEvent', {
        'eventName': eventName,
        'properties': properties ?? {},
      });
    } on PlatformException catch (e) {
      throw SetgreetTrackingException(
        e.message ?? 'Failed to track event',
        code: e.code,
      );
    }
  }

  /// Track screen views
  ///
  /// [screenName] - Name of the screen being viewed
  /// [properties] - Optional screen properties as key-value pairs
  ///
  /// Throws [SetgreetTrackingException] if screen tracking fails
  static Future<void> trackScreen(
    String screenName, {
    Map<String, dynamic>? properties,
  }) async {
    try {
      _ensureInitialized();

      if (screenName.trim().isEmpty) {
        throw SetgreetTrackingException('Screen name cannot be empty');
      }

      await _channel.invokeMethod('trackScreen', {
        'screenName': screenName,
        'properties': properties ?? {},
      });
    } on PlatformException catch (e) {
      throw SetgreetTrackingException(
        e.message ?? 'Failed to track screen',
        code: e.code,
      );
    }
  }

  /// Show a specific flow by ID
  ///
  /// [flowId] - The ID of the flow to display
  ///
  /// Throws [SetgreetFlowException] if showing flow fails
  static Future<void> showFlow(String flowId) async {
    try {
      _ensureInitialized();

      if (flowId.trim().isEmpty) {
        throw SetgreetFlowException('Flow ID cannot be empty');
      }

      await _channel.invokeMethod('showFlow', {'flowId': flowId});
    } on PlatformException catch (e) {
      throw SetgreetFlowException(
        e.message ?? 'Failed to show flow',
        code: e.code,
      );
    }
  }

  /// Sync the app's Material theme with Setgreet.
  ///
  /// Extracts the current Material 3 [ColorScheme] and [TextTheme] from the
  /// given [context] and posts them to the Setgreet backend, so flows render
  /// with matching colors and typography.
  ///
  /// Flutter must do this explicitly: the native SDKs auto-sync the HOST
  /// platform theme (UIKit system colors / the Android Activity theme), which
  /// for a Flutter app is framework defaults — not the app's [ThemeData].
  ///
  /// Call from a widget below [MaterialApp] (so [Theme.of] resolves the app
  /// theme), e.g. in a post-frame callback or after the first build.
  ///
  /// Throws [SetgreetThemeException] if the sync request fails.
  static Future<void> syncTheme(BuildContext context) async {
    _ensureInitialized();

    final colors = ThemeExtractor.extractColors(context);
    final typography = ThemeExtractor.extractTypography(context);

    await themeSyncApi.sync(
      apiUrl: _apiUrl,
      appKey: _appKey!,
      colors: colors,
      typography: typography,
    );
  }

  // MARK: - Flow Event Callbacks

  /// Sets callbacks to receive flow lifecycle events.
  ///
  /// Only one callbacks instance can be active at a time.
  /// Setting new callbacks will replace the previous ones.
  ///
  /// Example:
  /// ```dart
  /// Setgreet.setFlowCallbacks(
  ///   SetgreetFlowCallbacks()
  ///     ..onFlowStarted((event) {
  ///       print('Flow started: ${event.flowId}');
  ///     })
  ///     ..onFlowCompleted((event) {
  ///       analytics.log('flow_completed', {'duration': event.durationMs});
  ///     })
  ///     ..onActionTriggered((event) {
  ///       if (event.actionName != null) {
  ///         trackCustomEvent(event.actionName!);
  ///       }
  ///     }),
  /// );
  /// ```
  static void setFlowCallbacks(SetgreetFlowCallbacks? callbacks) {
    _callbacks = callbacks;
  }

  /// Get a stream of all flow events.
  ///
  /// Use this for reactive programming patterns.
  ///
  /// Example:
  /// ```dart
  /// Setgreet.flowEvents.listen((event) {
  ///   switch (event) {
  ///     case FlowStartedEvent():
  ///       print('Flow started: ${event.flowId}');
  ///     case FlowCompletedEvent():
  ///       print('Flow completed: ${event.flowId}');
  ///     // ... handle other events
  ///   }
  /// });
  /// ```
  static Stream<SetgreetFlowEvent> get flowEvents {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<dynamic, dynamic>.from(event as Map);
      return SetgreetFlowEvent.fromMap(map);
    });
  }

  /// Clears all registered flow callbacks.
  static void clearFlowCallbacks() {
    _callbacks = null;
  }

  /// Check if the SDK has been initialized
  static bool get isInitialized => _initialized;

  /// Get the anonymous ID assigned to this device.
  ///
  /// Automatically generated on initialization and persisted across app launches.
  /// A new anonymous ID is generated when [resetUser] is called.
  ///
  /// Returns null if the SDK has not been initialized.
  static Future<String?> get anonymousId async {
    try {
      return await _channel.invokeMethod<String>('getAnonymousId');
    } on PlatformException {
      return null;
    }
  }

  /// Ensure the SDK is initialized before performing operations
  static void _ensureInitialized() {
    if (!_initialized) {
      throw SetgreetInitializationException(
        'Setgreet SDK must be initialized before use. Call Setgreet.initialize() first.',
      );
    }
  }
}
