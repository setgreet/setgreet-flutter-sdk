import 'purchases.dart';

/// Reasons why a flow may be dismissed before completion.
enum DismissReason {
  /// User tapped the close button
  userClose,

  /// User tapped the skip button
  userSkip,

  /// User pressed the back button (hardware)
  backPress,

  /// Flow was replaced by a higher priority flow
  replaced,

  /// Flow was dismissed programmatically via SDK API
  programmatic,

  /// User swiped down to dismiss a bottom sheet
  swipeDown,

  /// Flow reached its end node
  completed,

  /// User chose to be reminded later
  remindLater;

  static DismissReason fromString(String value) {
    switch (value) {
      case 'userClose':
        return DismissReason.userClose;
      case 'userSkip':
        return DismissReason.userSkip;
      case 'backPress':
        return DismissReason.backPress;
      case 'replaced':
        return DismissReason.replaced;
      case 'programmatic':
        return DismissReason.programmatic;
      case 'swipeDown':
        return DismissReason.swipeDown;
      case 'completed':
        return DismissReason.completed;
      case 'remindLater':
        return DismissReason.remindLater;
      default:
        return DismissReason.userClose;
    }
  }
}

/// Categories of errors that may occur during flow operations.
enum FlowErrorType {
  /// Network-related error (connection, timeout, etc.)
  network,

  /// Error parsing flow data
  parse,

  /// Error displaying the flow UI
  display,

  /// Unknown or unclassified error
  unknown;

  static FlowErrorType fromString(String value) {
    switch (value) {
      case 'network':
        return FlowErrorType.network;
      case 'parse':
        return FlowErrorType.parse;
      case 'display':
        return FlowErrorType.display;
      default:
        return FlowErrorType.unknown;
    }
  }
}

/// Types of permissions that can be requested within a flow.
enum PermissionType {
  /// Push notification permission
  notification,

  /// Location access permission
  location,

  /// Camera access permission
  camera,

  /// App Tracking Transparency (iOS only; reported as notRequired on Android)
  tracking,

  /// Microphone access permission
  microphone,

  /// Photo library read access
  photoLibrary;

  static PermissionType fromString(String value) {
    switch (value) {
      case 'notification':
        return PermissionType.notification;
      case 'location':
        return PermissionType.location;
      case 'camera':
        return PermissionType.camera;
      case 'tracking':
        return PermissionType.tracking;
      case 'microphone':
        return PermissionType.microphone;
      case 'photoLibrary':
        return PermissionType.photoLibrary;
      default:
        return PermissionType.notification;
    }
  }
}

/// Results of a permission request.
enum PermissionResult {
  /// Permission was granted by the user
  granted,

  /// Permission was denied by the user
  denied,

  /// Permission was permanently denied (user must enable in settings)
  permanentlyDenied,

  /// Permission was already granted before the request
  alreadyGranted,

  /// Permission request was not required or not applicable
  notRequired;

  static PermissionResult fromString(String value) {
    switch (value) {
      case 'granted':
        return PermissionResult.granted;
      case 'denied':
        return PermissionResult.denied;
      case 'permanently_denied':
        return PermissionResult.permanentlyDenied;
      case 'already_granted':
        return PermissionResult.alreadyGranted;
      case 'not_required':
        return PermissionResult.notRequired;
      default:
        return PermissionResult.notRequired;
    }
  }
}

/// Sealed class hierarchy representing all flow lifecycle events.
sealed class SetgreetFlowEvent {
  final String flowId;
  final double timestamp;

  const SetgreetFlowEvent({
    required this.flowId,
    required this.timestamp,
  });

  factory SetgreetFlowEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type'] as String;
    final flowId = map['flowId'] as String;
    final timestamp = (map['timestamp'] as num).toDouble();

    switch (type) {
      case 'flowStarted':
        return FlowStartedEvent(
          flowId: flowId,
          screenCount: map['screenCount'] as int,
          timestamp: timestamp,
        );
      case 'flowCompleted':
        return FlowCompletedEvent(
          flowId: flowId,
          screenCount: map['screenCount'] as int,
          durationMs: (map['durationMs'] as num).toInt(),
          timestamp: timestamp,
        );
      case 'flowDismissed':
        return FlowDismissedEvent(
          flowId: flowId,
          reason: DismissReason.fromString(map['reason'] as String),
          screenIndex: map['screenIndex'] as int,
          screenCount: map['screenCount'] as int,
          durationMs: (map['durationMs'] as num).toInt(),
          timestamp: timestamp,
        );
      case 'screenChanged':
        return ScreenChangedEvent(
          flowId: flowId,
          fromIndex: map['fromIndex'] as int,
          toIndex: map['toIndex'] as int,
          screenCount: map['screenCount'] as int,
          timestamp: timestamp,
        );
      case 'actionTriggered':
        return ActionTriggeredEvent(
          flowId: flowId,
          actionType: map['actionType'] as String,
          actionName: map['actionName'] as String?,
          screenIndex: map['screenIndex'] as int,
          timestamp: timestamp,
        );
      case 'flowError':
        return FlowErrorEvent(
          flowId: flowId,
          errorType: FlowErrorType.fromString(map['errorType'] as String),
          message: map['message'] as String,
          timestamp: timestamp,
        );
      case 'customAction':
        return CustomActionEvent(
          flowId: flowId,
          data: _stringKeyedMap(map['data']),
          screenIndex: map['screenIndex'] as int,
          timestamp: timestamp,
        );
      case 'trackEvent':
        return TrackEventEvent(
          flowId: flowId,
          eventName: map['eventName'] as String,
          properties: _stringKeyedMap(map['properties']),
          screenIndex: map['screenIndex'] as int,
          timestamp: timestamp,
        );
      case 'remindLater':
        return RemindLaterEvent(
          flowId: flowId,
          screenIndex: map['screenIndex'] as int,
          timestamp: timestamp,
        );
      case 'permissionRequested':
        return PermissionRequestedEvent(
          flowId: flowId,
          permissionType:
              PermissionType.fromString(map['permissionType'] as String),
          result: PermissionResult.fromString(map['result'] as String),
          screenIndex: map['screenIndex'] as int,
          timestamp: timestamp,
        );
      case 'purchaseCompleted':
        return PurchaseCompletedEvent(
          flowId: flowId,
          screenId: map['screenId'] as String,
          componentId: map['componentId'] as String,
          productRef: map['productRef'] as String,
          provider: map['provider'] as String,
          accessRefs: _stringList(map['accessRefs']),
          timestamp: timestamp,
        );
      case 'purchaseCancelled':
        return PurchaseCancelledEvent(
          flowId: flowId,
          screenId: map['screenId'] as String,
          componentId: map['componentId'] as String,
          productRef: map['productRef'] as String,
          provider: map['provider'] as String,
          timestamp: timestamp,
        );
      case 'purchaseFailed':
        return PurchaseFailedEvent(
          flowId: flowId,
          screenId: map['screenId'] as String,
          componentId: map['componentId'] as String,
          productRef: map['productRef'] as String,
          provider: map['provider'] as String,
          error: _purchaseError(map['error']),
          timestamp: timestamp,
        );
      case 'purchasePending':
        return PurchasePendingEvent(
          flowId: flowId,
          screenId: map['screenId'] as String,
          componentId: map['componentId'] as String,
          productRef: map['productRef'] as String,
          provider: map['provider'] as String,
          timestamp: timestamp,
        );
      case 'restoreCompleted':
        return RestoreCompletedEvent(
          flowId: flowId,
          screenId: map['screenId'] as String,
          componentId: map['componentId'] as String,
          provider: map['provider'] as String,
          status: _restoreStatus(map['status']),
          accessRefs: _stringList(map['accessRefs']),
          timestamp: timestamp,
        );
      case 'restoreFailed':
        return RestoreFailedEvent(
          flowId: flowId,
          screenId: map['screenId'] as String,
          componentId: map['componentId'] as String,
          provider: map['provider'] as String,
          error: _purchaseError(map['error']),
          timestamp: timestamp,
        );
      default:
        throw ArgumentError('Unknown event type: $type');
    }
  }
}

/// A map from the platform channel, whose keys arrive as `Object?`, with
/// string keys at every level. Null when the native SDK sent none.
Map<String, Object?>? _stringKeyedMap(Object? value) =>
    value is Map ? _deepStringKeys(value) as Map<String, Object?> : null;

Object? _deepStringKeys(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _deepStringKeys(entry.value),
    };
  }
  if (value is List) {
    return value.map(_deepStringKeys).toList();
  }
  return value;
}

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const <String>[];

/// The `error` of a purchase event: `{code, providerCode, message}`. An
/// unrecognized or missing code is `unknown`.
SetgreetPurchaseError _purchaseError(Object? value) {
  if (value is! Map) {
    return const SetgreetPurchaseError(code: SetgreetPurchaseErrorCode.unknown);
  }
  final code = value['code'];
  final providerCode = value['providerCode'];
  final message = value['message'];
  return SetgreetPurchaseError(
    code: SetgreetPurchaseErrorCode.fromRawValue(code is String ? code : null),
    providerCode: providerCode is String ? providerCode : null,
    message: message is String ? message : null,
  );
}

SetgreetRestoreStatus _restoreStatus(Object? value) {
  for (final status in SetgreetRestoreStatus.values) {
    if (status.rawValue == value) return status;
  }
  throw ArgumentError('Unknown restore status: $value');
}

/// Emitted when a flow starts presenting to the user.
class FlowStartedEvent extends SetgreetFlowEvent {
  /// Total number of screens in the flow
  final int screenCount;

  const FlowStartedEvent({
    required super.flowId,
    required this.screenCount,
    required super.timestamp,
  });

  @override
  String toString() =>
      'FlowStartedEvent(flowId: $flowId, screenCount: $screenCount)';
}

/// Emitted when a flow is completed (user reached the last screen and closed).
class FlowCompletedEvent extends SetgreetFlowEvent {
  /// Total number of screens in the flow
  final int screenCount;

  /// How long the flow was displayed in milliseconds
  final int durationMs;

  const FlowCompletedEvent({
    required super.flowId,
    required this.screenCount,
    required this.durationMs,
    required super.timestamp,
  });

  @override
  String toString() =>
      'FlowCompletedEvent(flowId: $flowId, screenCount: $screenCount, durationMs: $durationMs)';
}

/// Emitted when a flow is dismissed before completion.
class FlowDismissedEvent extends SetgreetFlowEvent {
  /// The reason why the flow was dismissed
  final DismissReason reason;

  /// The screen index where dismissal occurred (0-based)
  final int screenIndex;

  /// Total number of screens in the flow
  final int screenCount;

  /// How long the flow was displayed in milliseconds
  final int durationMs;

  const FlowDismissedEvent({
    required super.flowId,
    required this.reason,
    required this.screenIndex,
    required this.screenCount,
    required this.durationMs,
    required super.timestamp,
  });

  @override
  String toString() =>
      'FlowDismissedEvent(flowId: $flowId, reason: $reason, screenIndex: $screenIndex)';
}

/// Emitted when user navigates between screens within a flow.
class ScreenChangedEvent extends SetgreetFlowEvent {
  /// The screen index navigated from (0-based)
  final int fromIndex;

  /// The screen index navigated to (0-based)
  final int toIndex;

  /// Total number of screens in the flow
  final int screenCount;

  const ScreenChangedEvent({
    required super.flowId,
    required this.fromIndex,
    required this.toIndex,
    required this.screenCount,
    required super.timestamp,
  });

  @override
  String toString() =>
      'ScreenChangedEvent(flowId: $flowId, from: $fromIndex, to: $toIndex)';
}

/// Emitted when the user taps a button or card that runs an action.
class ActionTriggeredEvent extends SetgreetFlowEvent {
  /// The action that ran, in snake_case: `next`, `previous`, `skip`,
  /// `dismiss`, `url`,
  /// `request_notification_permission`, `request_location_permission`,
  /// `request_camera_permission`, `request_tracking_permission`,
  /// `request_microphone_permission`, `request_photo_library_permission`,
  /// `request_review`, `share`, `open_settings`, `track_event`, `custom`,
  /// `purchase` or `restore_purchases`.
  final String actionType;

  /// The Track Event's event name when [actionType] is `track_event`, null
  /// otherwise.
  final String? actionName;

  /// The screen index where the action occurred (0-based)
  final int screenIndex;

  const ActionTriggeredEvent({
    required super.flowId,
    required this.actionType,
    this.actionName,
    required this.screenIndex,
    required super.timestamp,
  });

  @override
  String toString() =>
      'ActionTriggeredEvent(flowId: $flowId, actionType: $actionType, actionName: $actionName)';
}

/// Emitted when an error occurs during flow operations.
class FlowErrorEvent extends SetgreetFlowEvent {
  /// The category of error that occurred
  final FlowErrorType errorType;

  /// Human-readable error description
  final String message;

  const FlowErrorEvent({
    required super.flowId,
    required this.errorType,
    required this.message,
    required super.timestamp,
  });

  @override
  String toString() =>
      'FlowErrorEvent(flowId: $flowId, errorType: $errorType, message: $message)';
}

/// Emitted when the user taps a button or card whose action is Custom
/// Action. Use it to run your own code from a flow.
class CustomActionEvent extends SetgreetFlowEvent {
  /// The custom data configured on the action in the dashboard, null when
  /// none was configured
  final Map<String, Object?>? data;

  /// The screen index where the action occurred (0-based)
  final int screenIndex;

  const CustomActionEvent({
    required super.flowId,
    this.data,
    required this.screenIndex,
    required super.timestamp,
  });

  @override
  String toString() =>
      'CustomActionEvent(flowId: $flowId, data: $data, screenIndex: $screenIndex)';
}

/// Emitted when the user taps a button or card whose action is Track Event.
/// Use it to forward the event to your own analytics.
class TrackEventEvent extends SetgreetFlowEvent {
  /// The event name configured on the action in the dashboard
  final String eventName;

  /// The event properties configured on the action, null when none were
  /// configured
  final Map<String, Object?>? properties;

  /// The screen index where the action occurred (0-based)
  final int screenIndex;

  const TrackEventEvent({
    required super.flowId,
    required this.eventName,
    this.properties,
    required this.screenIndex,
    required super.timestamp,
  });

  @override
  String toString() =>
      'TrackEventEvent(flowId: $flowId, eventName: $eventName, properties: $properties)';
}

/// Emitted when the user taps a button or card whose action is Remind
/// Later. The flow then closes, with a [FlowDismissedEvent] whose reason is
/// [DismissReason.remindLater].
class RemindLaterEvent extends SetgreetFlowEvent {
  /// The screen index where the action occurred (0-based)
  final int screenIndex;

  const RemindLaterEvent({
    required super.flowId,
    required this.screenIndex,
    required super.timestamp,
  });

  @override
  String toString() =>
      'RemindLaterEvent(flowId: $flowId, screenIndex: $screenIndex)';
}

/// Emitted when a permission request completes within a flow.
class PermissionRequestedEvent extends SetgreetFlowEvent {
  /// The type of permission that was requested
  final PermissionType permissionType;

  /// The result of the permission request
  final PermissionResult result;

  /// The screen index where the permission was requested (0-based)
  final int screenIndex;

  const PermissionRequestedEvent({
    required super.flowId,
    required this.permissionType,
    required this.result,
    required this.screenIndex,
    required super.timestamp,
  });

  @override
  String toString() =>
      'PermissionRequestedEvent(flowId: $flowId, permissionType: $permissionType, result: $result)';
}

/// Emitted when a purchase through the registered purchase provider
/// succeeded.
class PurchaseCompletedEvent extends SetgreetFlowEvent {
  /// The paywall screen
  final String screenId;

  /// The purchase button
  final String componentId;

  /// The product ref that was bought
  final String productRef;

  /// The provider's `providerId`, e.g. "revenuecat"
  final String provider;

  /// The access (entitlement) refs the user now holds
  final List<String> accessRefs;

  const PurchaseCompletedEvent({
    required super.flowId,
    required this.screenId,
    required this.componentId,
    required this.productRef,
    required this.provider,
    required this.accessRefs,
    required super.timestamp,
  });

  @override
  String toString() =>
      'PurchaseCompletedEvent(flowId: $flowId, productRef: $productRef, accessRefs: $accessRefs)';
}

/// Emitted when the user cancelled a purchase.
class PurchaseCancelledEvent extends SetgreetFlowEvent {
  /// The paywall screen
  final String screenId;

  /// The purchase button
  final String componentId;

  /// The product ref the user was buying
  final String productRef;

  /// The provider's `providerId`, e.g. "revenuecat"
  final String provider;

  const PurchaseCancelledEvent({
    required super.flowId,
    required this.screenId,
    required this.componentId,
    required this.productRef,
    required this.provider,
    required super.timestamp,
  });

  @override
  String toString() =>
      'PurchaseCancelledEvent(flowId: $flowId, productRef: $productRef)';
}

/// Emitted when a purchase failed.
class PurchaseFailedEvent extends SetgreetFlowEvent {
  /// The paywall screen
  final String screenId;

  /// The purchase button
  final String componentId;

  /// The product ref the user was buying
  final String productRef;

  /// The provider's `providerId`, e.g. "revenuecat"
  final String provider;

  /// The normalized error, with the vendor's own code and message when known
  final SetgreetPurchaseError error;

  const PurchaseFailedEvent({
    required super.flowId,
    required this.screenId,
    required this.componentId,
    required this.productRef,
    required this.provider,
    required this.error,
    required super.timestamp,
  });

  @override
  String toString() =>
      'PurchaseFailedEvent(flowId: $flowId, productRef: $productRef, error: $error)';
}

/// Emitted when a purchase is pending approval (Ask to Buy, a deferred
/// payment).
class PurchasePendingEvent extends SetgreetFlowEvent {
  /// The paywall screen
  final String screenId;

  /// The purchase button
  final String componentId;

  /// The product ref the user was buying
  final String productRef;

  /// The provider's `providerId`, e.g. "revenuecat"
  final String provider;

  const PurchasePendingEvent({
    required super.flowId,
    required this.screenId,
    required this.componentId,
    required this.productRef,
    required this.provider,
    required super.timestamp,
  });

  @override
  String toString() =>
      'PurchasePendingEvent(flowId: $flowId, productRef: $productRef)';
}

/// Emitted when a restore finished, with or without something to restore.
class RestoreCompletedEvent extends SetgreetFlowEvent {
  /// The paywall screen
  final String screenId;

  /// The restore button
  final String componentId;

  /// The provider's `providerId`, e.g. "revenuecat"
  final String provider;

  /// [SetgreetRestoreStatus.restored] or
  /// [SetgreetRestoreStatus.nothingToRestore]
  final SetgreetRestoreStatus status;

  /// The access (entitlement) refs the user now holds
  final List<String> accessRefs;

  const RestoreCompletedEvent({
    required super.flowId,
    required this.screenId,
    required this.componentId,
    required this.provider,
    required this.status,
    required this.accessRefs,
    required super.timestamp,
  });

  @override
  String toString() =>
      'RestoreCompletedEvent(flowId: $flowId, status: ${status.rawValue}, accessRefs: $accessRefs)';
}

/// Emitted when a restore failed.
class RestoreFailedEvent extends SetgreetFlowEvent {
  /// The paywall screen
  final String screenId;

  /// The restore button
  final String componentId;

  /// The provider's `providerId`, e.g. "revenuecat"
  final String provider;

  /// The normalized error, with the vendor's own code and message when known
  final SetgreetPurchaseError error;

  const RestoreFailedEvent({
    required super.flowId,
    required this.screenId,
    required this.componentId,
    required this.provider,
    required this.error,
    required super.timestamp,
  });

  @override
  String toString() => 'RestoreFailedEvent(flowId: $flowId, error: $error)';
}
