import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'config.dart';
import 'exceptions.dart';
import 'flow_events.dart';
import 'flow_callbacks.dart';
import 'purchase_bridge.dart';
import 'purchases.dart';
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

  /// The flow events from the native SDK. Flutter keeps one Dart message
  /// handler per channel, and every `receiveBroadcastStream()` call replaces
  /// it, so this one stream is shared by the callbacks' listener and every
  /// [flowEvents] listener. Its platform subscription starts with the first
  /// listener and ends with the last.
  static final Stream<dynamic> _platformEvents =
      _eventChannel.receiveBroadcastStream();

  /// [flowEvents]: the platform events, parsed for each listener.
  static final Stream<SetgreetFlowEvent> _flowEvents =
      _platformEvents.map((event) {
    final map = Map<dynamic, dynamic>.from(event as Map);
    return SetgreetFlowEvent.fromMap(map);
  });

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

  /// Start listening for flow events from native, once: the subscription
  /// drives the callbacks and keeps the platform subscription open, so
  /// [flowEvents] listeners can come and go.
  static void _startEventListener() {
    _eventSubscription ??=
        _platformEvents.listen(_handleEvent, onError: _handleEventError);
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

  // MARK: - Purchase Provider

  /// Registers the app's purchase provider so paywall screens can load
  /// products, transact and branch on the outcome.
  ///
  /// [provider] is your [SetgreetPurchaseProvider], written on top of the
  /// purchase tool your app already uses (see the RevenueCat reference file
  /// in the example app). Configure that tool yourself first; Setgreet never
  /// configures it.
  ///
  /// [defaultSource] (the current offering unless you say otherwise) is
  /// loaded in the background right away, so the product catalog syncs to
  /// the dashboard before any paywall is shown. It is also the source a
  /// paywall screen reads when it has no plan picker. It is the only source
  /// whose catalog is synced.
  ///
  /// Call it after [initialize]: a registration made earlier could not sync
  /// the catalog. Register from the root isolate. A later call replaces the
  /// provider.
  ///
  /// Example:
  /// ```dart
  /// await Setgreet.setPurchaseProvider(SetgreetRevenueCatProvider());
  /// await Setgreet.setPurchaseProvider(
  ///   SetgreetRevenueCatProvider(),
  ///   defaultSource: const SetgreetPurchaseSource.offering('onboarding'),
  /// );
  /// ```
  ///
  /// Throws [SetgreetInitializationException] before [initialize], and
  /// [SetgreetException] when `provider.providerId` does not match
  /// `^[a-z][a-z0-9_]{0,39}$` (the backend rejects a catalog sync from any
  /// other id) or the native SDK rejects the registration.
  static Future<void> setPurchaseProvider(
    SetgreetPurchaseProvider provider, {
    SetgreetPurchaseSource defaultSource =
        const SetgreetPurchaseSource.currentOffering(),
  }) async {
    _ensureInitialized();

    final providerId = provider.providerId;
    if (!_providerIdPattern.hasMatch(providerId)) {
      throw SetgreetException(
        'Provider ID "$providerId" must match ^[a-z][a-z0-9_]{0,39}\$',
        code: 'INVALID_ARGUMENT',
      );
    }

    // The provider answers native calls from now on: the native side starts
    // loading the default source through it before this call returns. It is
    // committed (replacing a previous provider for good) only once the native
    // side accepted it; after a rejection the previous one answers again.
    final registration = SetgreetPurchaseBridge.begin(provider);
    try {
      await _channel.invokeMethod('setPurchaseProvider', {
        'providerId': providerId,
        'defaultSource': SetgreetPurchaseBridge.encodeSource(defaultSource),
        'firstInIsolate': registration.firstInIsolate,
      });
    } on PlatformException catch (e) {
      SetgreetPurchaseBridge.abandon(registration);
      throw SetgreetException(
        e.message ?? 'Failed to register the purchase provider',
        code: e.code,
      );
    } catch (_) {
      SetgreetPurchaseBridge.abandon(registration);
      rethrow;
    }
    SetgreetPurchaseBridge.commit(registration);
  }

  static final RegExp _providerIdPattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

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
  ///     ..onTrackEvent((event) {
  ///       analytics.log(event.eventName, event.properties);
  ///     }),
  /// );
  /// ```
  static void setFlowCallbacks(SetgreetFlowCallbacks? callbacks) {
    _callbacks = callbacks;
  }

  /// Get a stream of all flow events.
  ///
  /// Use this for reactive programming patterns. It works alongside
  /// [setFlowCallbacks]: both share one subscription to the native events,
  /// and cancelling a listener here never stops the callbacks.
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
  static Stream<SetgreetFlowEvent> get flowEvents => _flowEvents;

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

  /// Turns on Lottie animations in Setgreet flows.
  ///
  /// Call it once at startup, before the first flow shows. It does not need
  /// [initialize] first. Without it, a Lottie component in a flow renders
  /// nothing on iOS; the rest of the flow is unaffected.
  ///
  /// iOS: needs the opt-in `setgreet/Lottie` pod in your Podfile (see the
  /// README), which adds the `SetgreetSDKLottie` module and `lottie-ios`.
  /// Returns `false` when that pod is not installed.
  ///
  /// Android: the core SDK already includes Lottie, so this always returns
  /// `true` and changes nothing.
  ///
  /// Also returns `false` when the native plugin does not answer the call
  /// (a [MissingPluginException], for example on a platform without it).
  static Future<bool> registerLottie() async {
    try {
      return await _channel.invokeMethod<bool>('registerLottie') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
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
