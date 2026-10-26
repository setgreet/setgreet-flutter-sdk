# Setgreet Flutter SDK

[![pub package](https://img.shields.io/pub/v/setgreet.svg)](https://pub.dev/packages/setgreet)

Setgreet Flutter SDK allows you to show Setgreet flows in your Flutter app.

## Requirements

- Flutter: >=3.27.0
- Dart: >=3.6.0
- Android: minSdkVersion 23
- iOS: 15.0+

## Installation

### 1. Install the package

Add `setgreet` as a dependency in your `pubspec.yaml` file:

```yaml
dependencies:
  setgreet: ^1.0.0
```

Then run:

```bash
flutter pub get
```

### 2. iOS Setup

#### Install CocoaPods Dependencies

The iOS SDK will be automatically included via CocoaPods. Make sure to run:

```bash
cd ios && pod install
```

### 3. Android Setup

No additional setup required for Android.

### 4. Lottie animations (optional)

> [!WARNING]
> A missing or incomplete Podfile setup for Lottie still builds without errors, then **crashes at launch**, for example with `dyld: Library not loaded: @rpath/Lottie.framework/Lottie` (referenced from `SetgreetSDKLottie.framework`). Apply every Podfile line below. A Podfile allows only one `pre_install` and one `post_install` block, so **merge** these lines into the blocks your Podfile already has instead of adding second ones.

Lottie support is opt-in on iOS, so apps that don't use it stay smaller. Without it, a Lottie component in a flow renders nothing on iOS; the rest of the flow is unaffected. On Android the native SDK already includes Lottie.

**iOS:** add the `setgreet/Lottie` pod to your `ios/Podfile`. It brings in the `SetgreetSDKLottie` module and `lottie-ios`. `SetgreetSDKLottie` is a prebuilt dynamic framework that loads `@rpath/Lottie.framework`, built with library evolution, so `lottie-ios` must be built as a dynamic framework with library evolution too.

With dynamic frameworks (`use_frameworks!`, Flutter's default), add the pod and one setting to the `post_install` block Flutter generated:

```ruby
use_frameworks!

target 'Runner' do
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  pod 'setgreet/Lottie', :path => '.symlinks/plugins/setgreet/ios'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target) # already in your Podfile

    # Added for Setgreet Lottie
    if target.name == 'lottie-ios'
      target.build_configurations.each do |config|
        config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      end
    end
  end
end
```

**Static frameworks** (`use_frameworks! :linkage => :static`): pods are then built as static frameworks, and `SetgreetSDKLottie` cannot load a static Lottie, so the app crashes at launch with the error above. Keep the pod line and the `post_install` setting, and also build just `lottie-ios` as a dynamic framework in `pre_install` (merge it into yours if you already have one):

```ruby
use_frameworks! :linkage => :static

pre_install do |installer|
  installer.pod_targets.each do |pod|
    if pod.name == 'lottie-ios'
      def pod.build_type
        Pod::BuildType.dynamic_framework
      end
    end
  end
end
```

Then run `cd ios && pod install`.

**Register at startup**, once, before the first flow shows:

```dart
await Setgreet.registerLottie(); // true when Lottie can render
```

`registerLottie()` returns `false` on iOS when the `setgreet/Lottie` pod is not installed. On Android it always returns `true`. The [example app](example) does both steps.

## Usage

### Initialization

- Setgreet App Key: You can find your App Key at [Apps page](https://app.setgreet.com/apps).

Initialize the SDK in your Flutter app:

```dart
import 'package:setgreet/setgreet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Setgreet.initialize(
      'your_app_key_here',
      config: SetgreetConfig(
        debugMode: true, // Enable for development
      ),
    );
  } catch (e) {
    print('Failed to initialize Setgreet: $e');
  }

  runApp(MyApp());
}
```

### Theme sync

Sync your app's theme (colors + typography) to Setgreet so generated flows
match your brand. A Flutter app draws its UI from its own `ThemeData`, which
the native SDKs can't see — their auto-sync reads the host platform theme
(iOS system colors / the Android Activity theme), which for a Flutter app is
just framework defaults. So Flutter syncs its `ThemeData` explicitly:

```dart
import 'package:flutter/material.dart';
import 'package:setgreet/setgreet.dart';

// Call from a widget below MaterialApp (so Theme.of resolves your app theme),
// e.g. once after the first frame.
WidgetsBinding.instance.addPostFrameCallback((_) {
  Setgreet.syncTheme(context); // extracts ColorScheme + TextTheme, posts to Setgreet
});
```

`syncTheme` reads the current Material 3 `ColorScheme` and `TextTheme` from the
`BuildContext` and posts them to `POST /sdk/sync-theme`. It throws
`SetgreetThemeException` on failure. Point it at a non-production backend by
passing `apiUrl` in `SetgreetConfig` at `initialize` time.

### Identify User

Identifies a user for Setgreet analytics and flow management.

**Parameters:**

- `userId` (String): The unique identifier for the user
- `attributes` (Optional): Additional user attributes
- `operation` (Optional): Operation type ('create' or 'update', defaults to 'create')
- `locale` (Optional): User's locale (e.g., "en-US"). If not provided, uses device's default locale

```dart
await Setgreet.identifyUser(
  'user123',
  attributes: {
    'plan': 'premium',
    'signup_date': '2025-08-27',
  },
  operation: 'create',
  locale: 'en-US',
);
```

### Language

Call `setLocale` when the user picks a language in your app. The choice is saved on the device: it survives relaunches and `resetUser`, and it works before `initialize`, so anonymous users get localized flows too.

```dart
await Setgreet.setLocale('tr-TR'); // a BCP-47 tag
await Setgreet.setLocale(null);    // back to the device language
```

Flows are shown in, in order:

1. The `setLocale` override.
2. The last explicit `locale` passed to `identifyUser` for the current user.
3. The user's locale saved on the server.
4. The device language.

`null` or an empty string removes the override. An invalid tag is ignored with a warning, and the previous locale stays.

### Reset User

Clears user identification data and resets user session state for logout scenarios.

```dart
Setgreet.resetUser();
```

### Anonymous ID

The SDK automatically generates an anonymous ID on initialization, which persists across app launches. When `identifyUser` is called, the anonymous identity is merged with the identified user. A new anonymous ID is generated when `resetUser()` is called.

```dart
final anonId = await Setgreet.anonymousId;
```

### Show Flow

- Setgreet Flow ID: The flow ID is a unique identifier for the flow you want to show. You can get the flow ID from the flow's URL at the web app. For example, if the flow URL is `https://app.setgreet.com/flows/1234`, the flow ID is `1234`.

To show the Setgreet flow, call the following method:

```dart
// Show a specific flow
await Setgreet.showFlow('your_flow_id');
```

### Track Screen

Tracks a screen view for analytics and potential flow triggers.

**Parameters:**

- `screenName` (String): The name of the screen being viewed
- `properties` (Optional): Additional properties associated with the screen view

```dart
// Track screen view
await Setgreet.trackScreen('home_screen');

// With properties
await Setgreet.trackScreen(
  'product_details',
  properties: {
    'product_id': '12345',
    'category': 'electronics',
  },
);
```

### Track Event

Tracks custom events for analytics and flow triggers.

**Parameters:**

- `eventName` (String): The name of the custom event
- `properties` (Optional): Additional properties associated with the event

```dart
// Simple event
await Setgreet.trackEvent('button_clicked');

// Event with properties
await Setgreet.trackEvent(
  'purchase_completed',
  properties: {
    'product_id': '12345',
    'amount': 99.99,
    'currency': 'USD',
  },
);
```

### Flow Callbacks

Listen to flow lifecycle events to track user interactions and flow completion.

**Available Callbacks:**

- `onFlowStarted`: Called when a flow begins displaying
- `onFlowCompleted`: Called when user completes all screens in the flow
- `onFlowDismissed`: Called when user dismisses the flow before completion
- `onScreenChanged`: Called when user navigates between screens
- `onActionTriggered`: Called when a button's action is triggered, just before it runs, with the action's type (see [Action types](#action-types)). It also fires when required inputs on the screen then stop the action
- `onCustomAction`: Called when the user taps a button or card whose action is Custom Action, with the custom data configured on it
- `onTrackEvent`: Called when the user taps a button or card whose action is Track Event, with the event name and properties, so you can forward them to your own analytics
- `onPermissionRequested`: Called when a permission request completes
- `onError`: Called when an error occurs during flow operations, with an error type (`network`, `parse`, `display` or `unknown`) and a message
- `onPurchaseCompleted`, `onPurchaseCancelled`, `onPurchaseFailed`, `onPurchasePending`, `onRestoreCompleted`, `onRestoreFailed`: paywall outcomes (see [Purchases and paywalls](#purchases-and-paywalls))

**Using Callbacks Builder:**

```dart
Setgreet.setFlowCallbacks(
  SetgreetFlowCallbacks()
    ..onFlowStarted((event) {
      print('Flow started: ${event.flowId}');
      print('Total screens: ${event.screenCount}');
    })
    ..onFlowCompleted((event) {
      print('Flow completed: ${event.flowId}');
      print('Duration: ${event.durationMs}ms');
    })
    ..onFlowDismissed((event) {
      print('Flow dismissed: ${event.flowId}');
      print('Reason: ${event.reason}');
      print('Screen: ${event.screenIndex + 1}/${event.screenCount}');
    })
    ..onScreenChanged((event) {
      print('Screen changed: ${event.fromIndex + 1} -> ${event.toIndex + 1}');
    })
    ..onActionTriggered((event) {
      print('Action: ${event.actionType} on screen ${event.screenIndex + 1}');
    })
    ..onCustomAction((event) {
      print('Custom action: ${event.data}');
    })
    ..onTrackEvent((event) {
      // Forward to your own analytics
      print('Track event: ${event.eventName} ${event.properties}');
    })
    ..onPermissionRequested((event) {
      print('Permission: ${event.permissionType} -> ${event.result}');
    })
    ..onError((event) {
      print('Error: ${event.errorType} - ${event.message}');
    }),
);
```

**Using Stream API:**

```dart
// Listen to all events as a stream
Setgreet.flowEvents.listen((event) {
  switch (event) {
    case FlowStartedEvent():
      print('Flow started: ${event.flowId}');
    case FlowCompletedEvent():
      print('Flow completed: ${event.flowId}');
    case FlowDismissedEvent():
      print('Flow dismissed: ${event.reason}');
    case ScreenChangedEvent():
      print('Screen changed: ${event.fromIndex} -> ${event.toIndex}');
    case ActionTriggeredEvent():
      print('Action: ${event.actionType}');
    case CustomActionEvent():
      print('Custom action: ${event.data}');
    case TrackEventEvent():
      print('Track event: ${event.eventName}');
    case PermissionRequestedEvent():
      print('Permission: ${event.permissionType} -> ${event.result}');
    case FlowErrorEvent():
      print('Error: ${event.errorType}');
    case PurchaseCompletedEvent():
      print('Purchased: ${event.productRef}');
    case PurchaseCancelledEvent() ||
        PurchaseFailedEvent() ||
        PurchasePendingEvent() ||
        RestoreCompletedEvent() ||
        RestoreFailedEvent():
      print('Paywall outcome: $event');
  }
});
```

`SetgreetFlowEvent` is sealed: a `switch` over it must cover every event type, or end with a `default` case.

The callbacks and `Setgreet.flowEvents` work together: they share one subscription to the native events, so you can use both, listen to `flowEvents` more than once, and cancel a `flowEvents` listener without stopping the callbacks.

**Dismiss Reasons:**

| Reason | Description |
|--------|-------------|
| `userClose` | User tapped the close button |
| `userSkip` | User tapped the skip button |
| `backPress` | User pressed the back button (hardware) |
| `replaced` | Flow was replaced by a higher priority flow |
| `programmatic` | Flow was dismissed programmatically |
| `swipeDown` | User swiped down to dismiss a bottom sheet |
| `completed` | Flow reached its end node |

**Permission Types:**

| Type | Description |
|------|-------------|
| `notification` | Push notification permission |
| `location` | Location access permission |
| `camera` | Camera access permission |
| `tracking` | App Tracking Transparency (iOS only; `notRequired` on Android) |
| `microphone` | Microphone access permission |
| `photoLibrary` | Photo library read access |

**Permission Results:**

| Result | Description |
|--------|-------------|
| `granted` | Permission was granted by the user |
| `denied` | Permission was denied by the user |
| `permanentlyDenied` | Permission was permanently denied |
| `alreadyGranted` | Permission was already granted |
| `notRequired` | Permission request was not required |

#### Action types

`ActionTriggeredEvent.actionType` is one of these snake_case strings, the same on iOS and Android:

| Action type | Action |
|-------------|--------|
| `next`, `previous` | Go to the next or previous screen |
| `skip` | Skip the flow |
| `dismiss` | Close the flow |
| `url` | Open a URL |
| `request_notification_permission`, `request_location_permission`, `request_camera_permission`, `request_tracking_permission`, `request_microphone_permission`, `request_photo_library_permission` | Request a permission (the result fires `onPermissionRequested`) |
| `request_review` | Ask for an App Store or Google Play review |
| `share` | Open the share sheet |
| `open_settings` | Open the app's system settings |
| `track_event` | Track an event (also fires `onTrackEvent`); `actionName` is the event name |
| `custom` | Custom action (also fires `onCustomAction`) |
| `purchase`, `restore_purchases` | Buy a product or restore purchases (the outcome fires the purchase events) |

`actionName` is the Track Event's event name for `track_event` and null for every other action.

#### Custom action and track event events

| Event | Fields |
|-------|--------|
| `CustomActionEvent` | `flowId`, `data` (`Map<String, Object?>?`, the custom data configured in the dashboard), `screenIndex`, `timestamp` |
| `TrackEventEvent` | `flowId`, `eventName`, `properties` (`Map<String, Object?>?`), `screenIndex`, `timestamp` |

On iOS, `data` and `properties` keep their JSON types (numbers, booleans, nested maps and lists). On Android, every value arrives as a string, and a nested object or array as `null`, so read values defensively, for example `int.tryParse('${event.data?['count']}')`.

On Android, the plugin receives `onCustomAction` and `onTrackEvent` through the native SDK's `Setgreet.setFlowListener`, which holds a single listener. `Setgreet.initialize` replaces a listener your Android code set earlier, and a `Setgreet.setFlowListener` call from your Android code after `initialize` stops these two events in Dart. Use the Dart callbacks or `Setgreet.flowEvents` instead of a native listener.

## Purchases and paywalls

Setgreet renders paywall screens natively and branches the flow on the outcome. Your app implements one Dart interface, `SetgreetPurchaseProvider`, on top of the purchase tool it already uses (RevenueCat, Adapty, StoreKit, Google Play Billing). Setgreet wraps no vendor SDK, stores no vendor key and keeps no entitlement state; the SDK owns the loading state, the plan picker, live prices in copy, the purchase lock, branching, analytics and syncing your product catalog to the dashboard.

### Register a provider

Configure your purchase tool yourself, then register the provider after `Setgreet.initialize`:

```dart
await Setgreet.initialize('your_app_key_here');

// Your own RevenueCat setup (Setgreet never configures it).
await Purchases.configure(PurchasesConfiguration('<your RevenueCat public SDK key>'));

await Setgreet.setPurchaseProvider(SetgreetRevenueCatProvider());
```

`defaultSource` (the current offering unless you pass another) is loaded in the background right away, so the catalog reaches the dashboard before any paywall is shown. It is also the source a paywall screen without a plan picker reads, and the only source whose catalog is synced:

```dart
await Setgreet.setPurchaseProvider(
  SetgreetRevenueCatProvider(),
  defaultSource: const SetgreetPurchaseSource.offering('onboarding'),
);
```

A registration made before `initialize` throws `SetgreetInitializationException`; a `providerId` that does not match `^[a-z][a-z0-9_]{0,39}$` throws `SetgreetException`. A later call replaces the provider. Register from the root isolate only: the native SDK calls the provider through the root isolate's platform channel.

### The interface

```dart
abstract class SetgreetPurchaseProvider {
  String get providerId; // "revenuecat", "adapty", ... (^[a-z][a-z0-9_]{0,39}$)
  Future<List<SetgreetPurchaseProduct>> loadProducts(SetgreetPurchaseSource source);
  Future<SetgreetPurchaseResult> purchase(String productRef, SetgreetPurchaseSource source);
  Future<SetgreetRestoreResult> restorePurchases();
  Future<SetgreetPurchaseAccessState?> accessState(); // null = cannot say
  void trackPaywallImpression(SetgreetPaywallImpressionContext context) {} // optional
  void setAttributes(Map<String, String> attributes) {} // optional
  Future<void> identify(String userId) async {} // optional
  Future<void> reset() async {} // optional
}
```

Extend the class; the optional methods default to no-ops.

- **Refs are per source.** A product ref (a RevenueCat package identifier such as `$rc_annual`) is unique only within its source, since every offering can have a `$rc_annual`. `purchase` receives the source the product was loaded from: buy the product you returned for that ref from that source.
- **Errors.** `loadProducts` throws a `SetgreetPurchaseError` (`providerNotInitialized`, `productNotFound`, `networkError`, ...) when products cannot be loaded; any other error is reported as `unknown`. `purchase` and `restorePurchases` report every outcome as a status; a thrown `SetgreetPurchaseError` becomes `failed` with its code, any other error `failed` with `unknown`. `accessState` returns null when it cannot say, and a thrown error counts as null.
- **`priceAmount`** is a `double` (the type purchases_flutter reports). The native SDKs keep prices as exact decimals: the plugin converts the value through its shortest decimal form, so `49.99` stays `49.99`.
- **Identity.** `identify` and `reset` run when you call `Setgreet.identifyUser` / `Setgreet.resetUser`. Implement them only if Setgreet should drive your purchase tool's identity; the RevenueCat reference leaves them empty because your app already calls `Purchases.logIn` / `logOut`.
- **Fire-and-forget methods.** `trackPaywallImpression` and `setAttributes` return `void`, so nothing awaits them: if you override them with an `async` body, catch your own errors inside it.

### RevenueCat reference provider

[`example/lib/setgreet_revenuecat_provider.dart`](example/lib/setgreet_revenuecat_provider.dart) is a complete provider backed by RevenueCat. Copy it into your app; it compiles against the `purchases_flutter` dependency your app already has (10.3.0 or later) and adds nothing to Setgreet's own dependencies. The example app shows where to paste your RevenueCat keys (`example/lib/config.dart`). On Google Play it drops the app name Google Play appends to product titles, so "Premium Annual (Your App)" reaches your paywall as "Premium Annual".

### Platform notes

- The native SDK calls your Dart provider on the root isolate. On a paywall screen it waits up to 10 s for `loadProducts` (and for `accessState` when the screen skips users who already have access) before the screen follows its "unavailable" policy. `purchase` and `restorePurchases` have no time limit, since a store sheet can stay open for minutes.
- If your provider never answers `loadProducts` or `accessState`, the plugin stops waiting after 30 s. `identify` and `reset` have no time limit: the native SDK runs them one after another and writes the user's access attributes once they are done, so cutting a slow one short could attribute the previous user's access to the new one.
- If the Flutter engine is torn down while a call is waiting, the call is answered as if no provider were registered (a purchase or restore ends as `failed` with `not_configured`), so a paywall button never stays locked.
- Android: the paywall runs in Setgreet's own activity, while your provider lives in the engine of your `FlutterActivity`, and purchases_flutter launches Google Play Billing from that `FlutterActivity`. If that activity is destroyed underneath the paywall, loads and purchases fail as engine-detached.
- With several Flutter engines, the native SDK keeps only the last registration.
- During development, a hot restart drops the Dart side of any call in flight. Such a call is answered as if no provider were registered once the restarted app registers its provider again.

### Purchase events

```dart
Setgreet.setFlowCallbacks(
  SetgreetFlowCallbacks()
    ..onPurchaseCompleted((event) => print('${event.productRef}: ${event.accessRefs}'))
    ..onPurchaseCancelled((event) => print('Cancelled ${event.productRef}'))
    ..onPurchaseFailed((event) => print('Failed: ${event.error.code.rawValue} ${event.error.providerCode}'))
    ..onPurchasePending((event) => print('Pending ${event.productRef}'))
    ..onRestoreCompleted((event) => print('Restore: ${event.status.rawValue}'))
    ..onRestoreFailed((event) => print('Restore failed: ${event.error.code.rawValue}')),
);
```

Each of these events carries `flowId`, `screenId`, `componentId` (the button), `provider` and `timestamp`. The four purchase events add `productRef`; `PurchaseCompletedEvent` and `RestoreCompletedEvent` add `accessRefs` (the access the user now holds); `RestoreCompletedEvent` adds `status` (`restored` or `nothingToRestore`); the two failure events add `error` (`code`, `providerCode`, `message`). The same events arrive on `Setgreet.flowEvents`.

## External Data in Flows

Flows can render data fetched from **your own** API — a product list filtered by answers the user gave earlier in the same flow. You register the endpoint once in the Setgreet dashboard (Data Sources), bind it into a screen, and it renders.

**Nothing to do on the Flutter side.** The feature needs no code, no new permission and no new dependency in your app.

What is worth knowing:

- **Use plugin 1.2.0 or newer.** On an older version the screen renders without its data rather than failing.
- **Setgreet calls your API from its servers, not from the device**, so your endpoint must be reachable over HTTPS from the public internet. Setgreet signs each request and asserts the end user's id; verify the signature on your side.
- **A failure degrades, it does not blank.** If your API is slow or down, the screen renders without the data-bound parts. Only if the flow author explicitly chose "skip screen" is it passed over.
- **Answers reach your API by input name.** An input named `goal` in the editor arrives as `goal`. Attributes you set via `identifyUser` are available to it too.

See [External Data](https://setgreet.com/docs/personalization/external-data) for the endpoint contract and the signature-verification recipe.

## Permissions Setup

If your flows use permission buttons, add the required keys to your `Info.plist` (iOS):

```xml
<!-- For location permission -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Your description for location usage</string>

<!-- For camera permission -->
<key>NSCameraUsageDescription</key>
<string>Your description for camera usage</string>

<!-- For tracking permission (App Tracking Transparency) -->
<key>NSUserTrackingUsageDescription</key>
<string>Your description for tracking usage</string>

<!-- For microphone permission -->
<key>NSMicrophoneUsageDescription</key>
<string>Your description for microphone usage</string>

<!-- For photo library permission -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Your description for photo library usage</string>
```

Note: Notification permission doesn't require an Info.plist key. A missing key is logged, reported as `notRequired`, and the flow advances.

On Android the SDK declares only `INTERNET`; declare the permissions your flows request in your app's `AndroidManifest.xml`: `POST_NOTIFICATIONS` (API 33+), `ACCESS_FINE_LOCATION`, `CAMERA`, `RECORD_AUDIO`, and `READ_MEDIA_IMAGES` (API 33+) or `READ_EXTERNAL_STORAGE` below. Tracking has no Android equivalent and advances immediately.

A screen can also carry a permission gate ("Skip when granted" in the editor): the SDK skips the primer when the permission is already granted, with nothing to do on the Flutter side.

### General Issues

If you continue to have issues, please [open an issue](https://github.com/setgreet/setgreet-flutter-sdk/issues) with:

- Your Flutter version
- iOS/Android version
- Error messages
- Steps to reproduce

## Development

Dart tests and the analyzer, from the repository root and from `example/`:

```bash
flutter test && flutter analyze
cd example && flutter test && flutter analyze
```

The Android side of the purchase bridge has JVM unit tests in `android/src/test`. Run them through the example app's Gradle build:

```bash
cd example/android && ./gradlew :setgreet:testDebugUnitTest
```

The iOS side has XCTest cases in `example/ios/RunnerTests`. Build the example once first (the build runs `pod install`), then run them on a simulator:

```bash
cd example
flutter build ios --simulator --no-codesign
cd ios
xcodebuild test -workspace Runner.xcworkspace -scheme Runner -only-testing:RunnerTests \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The example targets iOS 15.1 and builds the simulator app for arm64 only (`EXCLUDED_ARCHS` on the Runner target), so both commands work with Xcode 27 as they are. On an Intel Mac, remove that exclusion to run the example in a simulator.
