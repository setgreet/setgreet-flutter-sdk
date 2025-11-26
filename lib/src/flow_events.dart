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
  programmatic;

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
      default:
        throw ArgumentError('Unknown event type: $type');
    }
  }
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

/// Emitted when a button action is triggered by the user.
class ActionTriggeredEvent extends SetgreetFlowEvent {
  /// The type of action performed (close, next, skip, etc.)
  final String actionType;

  /// Custom event name if configured in dashboard, null otherwise
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
