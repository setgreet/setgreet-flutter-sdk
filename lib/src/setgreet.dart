import 'package:flutter/services.dart';
import 'config.dart';
import 'exceptions.dart';

/// Main Setgreet SDK class
class Setgreet {
  static const MethodChannel _channel = MethodChannel('setgreet');

  static bool _initialized = false;

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

      final configMap = (config ?? const SetgreetConfig()).toMap();
      configMap['appKey'] = appKey;

      await _channel.invokeMethod('initialize', configMap);
      _initialized = true;
    } on PlatformException catch (e) {
      throw SetgreetInitializationException(
        e.message ?? 'Failed to initialize Setgreet SDK',
        code: e.code,
      );
    }
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

  /// Check if the SDK has been initialized
  static bool get isInitialized => _initialized;

  /// Ensure the SDK is initialized before performing operations
  static void _ensureInitialized() {
    if (!_initialized) {
      throw SetgreetInitializationException(
        'Setgreet SDK must be initialized before use. Call Setgreet.initialize() first.',
      );
    }
  }
}
