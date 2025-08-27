# Setgreet Flutter SDK

[![pub package](https://img.shields.io/pub/v/setgreet.svg)](https://pub.dev/packages/setgreet)

Setgreet Flutter SDK allows you to show Setgreet flows in your Flutter app.

## Requirements

- Flutter: >=3.0.0
- Dart: >=3.0.0
- Android: minSdkVersion 21
- iOS: 11.0+

## Installation

### 1. Install the package

Add `setgreet` as a dependency in your `pubspec.yaml` file:

```yaml
dependencies:
  setgreet: ^0.1.0
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

- Setgreet App Key: You can get the app key while creating a new app in the Setgreet flow editor.

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

### Identify User

Identifies a user for Setgreet analytics and flow management.

**Parameters:**

- `userId` (String): The unique identifier for the user
- `attributes` (Optional): Additional user attributes

```dart
// Simple user identification
await Setgreet.identifyUser('user123');

// With custom attributes
await Setgreet.identifyUser(
  'user123',
  attributes: {
    'plan': 'premium',
    'locale': 'en-US',
    'signup_date': '2025-08-27',
  },
);
```

### Reset User

Clears user identification data and resets user session state for logout scenarios.

```dart
await Setgreet.resetUser();
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

### General Issues

If you continue to have issues, please [open an issue](https://github.com/setgreet/setgreet-flutter-sdk/issues) with:

- Your Flutter version
- iOS/Android version
- Error messages
- Steps to reproduce
