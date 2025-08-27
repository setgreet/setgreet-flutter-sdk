# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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