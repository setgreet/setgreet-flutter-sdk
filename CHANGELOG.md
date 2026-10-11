# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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