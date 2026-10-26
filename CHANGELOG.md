# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Setgreet.setLocale(String? locale)` sets the language flows are shown in on this device, for example from your app's language picker. The choice is saved on the device, survives relaunches and `resetUser`, and works before `initialize`. `null` or an empty string returns to the device language, and an invalid tag is ignored with a warning. Flows are shown in the `setLocale` override, else the last explicit `identifyUser` locale for the current user, else the user's locale saved on the server, else the device language.
- `Setgreet.registerLottie()` turns on Lottie animations in flows. On iOS it needs the opt-in `setgreet/Lottie` pod (see the README); without it, Lottie components render nothing on iOS. On Android the native SDK already includes Lottie, so the call always returns `true`. It returns `false`, rather than throwing, when the native plugin does not answer. The README covers Podfiles with static frameworks (`use_frameworks! :linkage => :static`).

## [1.8.0] - 2026-10-16

This release carries the version of the native SDKs it bundles (1.8.0).

### Changed

- Upgraded native Android and iOS SDK dependencies to 1.8.0. `onActionTriggered` now reports each button's action as it runs, and `onError` reports a flow that could not be shown, with its error type. If you forward Track Event buttons to your analytics, do it in `onTrackEvent` only, since `onActionTriggered` reports the same tap.

### Added

- `onCustomAction` and `onTrackEvent` callbacks, with matching `CustomActionEvent` and `TrackEventEvent` on `Setgreet.flowEvents`. They fire when the user taps a button or card whose action is Custom Action (with its custom data) or Track Event (with the event name and properties, to forward to your own analytics).
  - On Android, the plugin receives these events through the native SDK's single `Setgreet.setFlowListener` slot. `Setgreet.initialize` replaces a listener set from Android code before it, and a `Setgreet.setFlowListener` call from Android code after it stops these events in Dart.

### Breaking Changes

- `SetgreetFlowEvent` has three new subclasses (`CustomActionEvent`, `TrackEventEvent`, `RemindLaterEvent`). An exhaustive `switch` over `SetgreetFlowEvent` without a `default` no longer compiles: add cases for the new events, or a `default` case. The version number follows the version of the bundled native SDKs (see 1.6.0), so this breaking change ships in a minor release.

### Fixed

- The minimum Flutter version in `pubspec.yaml` is now 3.27.0. Since 1.1.0, theme sync has used `Color.r`, `.g` and `.b` (Flutter 3.27) and `ColorScheme.surfaceContainerHighest` (Flutter 3.22), so the package did not compile on older Flutter versions even though pub accepted them.

## [1.7.0] - 2026-10-11

This release carries the version of the native Android SDK it bundles (1.7.0). The native iOS SDK stays at 1.6.0.

### Changed

- Upgraded native Android SDK dependency to 1.7.0. The Android SDK no longer sets a network security config for your whole app, so your app's own network policy applies again. If your app relied on the SDK's config, for example to trust user-installed CA certificates, or references `@xml/network_security_config` without defining it, add a network security config of your own.

### Fixed

- Flow callbacks (`setFlowCallbacks`, including `onPurchaseCompleted`) stopped firing once the app listened to `Setgreet.flowEvents`, and cancelling that listener stopped every event until `initialize` ran again. The callbacks and every `flowEvents` listener now share one subscription to the native events.

## [1.6.0] - 2026-10-11

This release carries the version of the native SDKs it bundles (1.6.0), which shipped the same new purchase events as a minor release.

### Added

- Purchases and paywalls: `Setgreet.setPurchaseProvider` registers a `SetgreetPurchaseProvider` that your app implements in Dart on top of the purchase tool it already uses (RevenueCat, Adapty, StoreKit, Google Play Billing). Paywall screens load products, purchase, restore and branch on the outcome through it.
- Purchase events: `onPurchaseCompleted`, `onPurchaseCancelled`, `onPurchaseFailed`, `onPurchasePending`, `onRestoreCompleted` and `onRestoreFailed` callbacks, with matching `SetgreetFlowEvent` subclasses on `Setgreet.flowEvents`.
- A copy-paste RevenueCat reference provider in the example app (`example/lib/setgreet_revenuecat_provider.dart`, for `purchases_flutter` 10.3.0 or later).

### Breaking Changes

- `SetgreetFlowEvent` has six new subclasses (`PurchaseCompletedEvent`, `PurchaseCancelledEvent`, `PurchaseFailedEvent`, `PurchasePendingEvent`, `RestoreCompletedEvent`, `RestoreFailedEvent`). An exhaustive `switch` over `SetgreetFlowEvent` without a `default` no longer compiles: add cases for the new events, or a `default` case.

### Changed

- Upgraded native iOS SDK dependency to 1.6.0
- Upgraded native Android SDK dependency to 1.6.0

## [1.1.0] - 2026-06-19

### Added

- `syncTheme()` method to push your app's brand colors and fonts to Setgreet so flows match your app
- New flow components, available automatically via the updated native SDKs: Switch, Segmented Control, Chip, Stepper, and Quiz
- Button icons, native entrance animations (fade, slide-up, scale), and accessibility label support

### Changed

- Upgraded native iOS SDK dependency to 1.1.0
- Upgraded native Android SDK dependency to 1.1.0

## [1.0.0] - 2026-02-28

### Breaking Changes

- Minimum iOS version raised from 11.0 to 15.0
- Minimum Android SDK version raised from 21 to 23

### Added

- `anonymousId` static getter for accessing the device's anonymous identifier
- New dismiss reasons: `swipeDown`, `completed`, `remindLater`

### Changed

- Upgraded native iOS SDK dependency from 0.5.0 to 1.0.0
- Upgraded native Android SDK dependency from 0.6.0 to 1.0.0

## [0.2.0] - 2025-10-01

### Added

- Operation support in `identifyUser` method for better user state management
- Locale parameter in `identifyUser` method to support localization

### Changed

- Upgraded native Android SDK version
- Upgraded native iOS SDK version
- Enhanced `identifyUser` API with additional parameters

## [0.1.0] - 2025-08-27

### Added

- Initial release of Setgreet Flutter SDK
- Core functionality:
  - SDK initialization with app key and configuration
  - User identification with custom attributes
  - Event tracking with properties
  - Screen tracking with properties
  - Flow display functionality
  - User session reset
- Cross-platform support for Android and iOS
- Comprehensive error handling with custom exceptions
- Debug mode support for development
- Example Flutter app demonstrating all features
- Complete documentation and API reference

### Technical Details

- Built with Flutter 3.0+ and Dart 3.0+
- Android implementation using Kotlin and MethodChannel
- iOS implementation using Swift and FlutterMethodChannel
- Platform-specific native SDK integrations
- Proper error propagation and exception handling