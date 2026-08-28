# Setgreet Flutter SDK

[![pub package](https://img.shields.io/pub/v/setgreet.svg)](https://pub.dev/packages/setgreet)

Setgreet Flutter SDK allows you to show Setgreet flows in your Flutter app.

## Requirements

- Flutter: >=3.0.0
- Dart: >=3.0.0
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
- `onActionTriggered`: Called when user interacts with buttons
- `onPermissionRequested`: Called when a permission request completes
- `onError`: Called when an error occurs during flow operations

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
      print('Action: ${event.actionType}');
      if (event.actionName != null) {
        print('Custom event name: ${event.actionName}');
      }
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
    case PermissionRequestedEvent():
      print('Permission: ${event.permissionType} -> ${event.result}');
    case FlowErrorEvent():
      print('Error: ${event.errorType}');
  }
});
```

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

**Permission Results:**

| Result | Description |
|--------|-------------|
| `granted` | Permission was granted by the user |
| `denied` | Permission was denied by the user |
| `permanentlyDenied` | Permission was permanently denied |
| `alreadyGranted` | Permission was already granted |
| `notRequired` | Permission request was not required |

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
```

Note: Notification permission doesn't require an Info.plist key.

### General Issues

If you continue to have issues, please [open an issue](https://github.com/setgreet/setgreet-flutter-sdk/issues) with:

- Your Flutter version
- iOS/Android version
- Error messages
- Steps to reproduce
