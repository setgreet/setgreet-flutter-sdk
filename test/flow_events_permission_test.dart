import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

void main() {
  group('PermissionType.fromString', () {
    test('maps every wire value the native SDKs emit', () {
      expect(PermissionType.fromString('notification'),
          PermissionType.notification);
      expect(PermissionType.fromString('location'), PermissionType.location);
      expect(PermissionType.fromString('camera'), PermissionType.camera);
      expect(PermissionType.fromString('tracking'), PermissionType.tracking);
      expect(
          PermissionType.fromString('microphone'), PermissionType.microphone);
      expect(PermissionType.fromString('photoLibrary'),
          PermissionType.photoLibrary);
    });

    test(
        'an unknown value from a newer native SDK falls back rather than throwing',
        () {
      // The fallback is what made the wrapper release mandatory alongside the
      // native ones: before these members existed, a tracking event was
      // silently reported as a notification event.
      expect(
          PermissionType.fromString('healthKit'), PermissionType.notification);
    });
  });
}
