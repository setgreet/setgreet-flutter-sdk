import 'flow_events.dart';

/// Callback type definitions for flow events
typedef FlowStartedCallback = void Function(FlowStartedEvent event);
typedef FlowCompletedCallback = void Function(FlowCompletedEvent event);
typedef FlowDismissedCallback = void Function(FlowDismissedEvent event);
typedef ScreenChangedCallback = void Function(ScreenChangedEvent event);
typedef ActionTriggeredCallback = void Function(ActionTriggeredEvent event);
typedef PermissionRequestedCallback = void Function(
    PermissionRequestedEvent event);
typedef FlowErrorCallback = void Function(FlowErrorEvent event);

/// Container for flow event callbacks using builder pattern.
///
/// Example usage with builder:
/// ```dart
/// Setgreet.setFlowCallbacks(
///   SetgreetFlowCallbacks()
///     ..onFlowStarted((event) {
///       print('Flow started: ${event.flowId}');
///     })
///     ..onFlowCompleted((event) {
///       print('Flow completed in ${event.durationMs}ms');
///     })
///     ..onFlowDismissed((event) {
///       if (event.reason == DismissReason.userSkip) {
///         promptForFeedback();
///       }
///     })
///     ..onActionTriggered((event) {
///       if (event.actionName != null) {
///         trackCustomEvent(event.actionName!);
///       }
///     }),
/// );
/// ```
class SetgreetFlowCallbacks {
  FlowStartedCallback? _onStarted;
  FlowCompletedCallback? _onCompleted;
  FlowDismissedCallback? _onDismissed;
  ScreenChangedCallback? _onScreenChanged;
  ActionTriggeredCallback? _onActionTriggered;
  PermissionRequestedCallback? _onPermissionRequested;
  FlowErrorCallback? _onError;

  /// Register a callback for when a flow starts presenting.
  SetgreetFlowCallbacks onFlowStarted(FlowStartedCallback callback) {
    _onStarted = callback;
    return this;
  }

  /// Register a callback for when a flow is completed.
  SetgreetFlowCallbacks onFlowCompleted(FlowCompletedCallback callback) {
    _onCompleted = callback;
    return this;
  }

  /// Register a callback for when a flow is dismissed.
  SetgreetFlowCallbacks onFlowDismissed(FlowDismissedCallback callback) {
    _onDismissed = callback;
    return this;
  }

  /// Register a callback for when the user navigates between screens.
  SetgreetFlowCallbacks onScreenChanged(ScreenChangedCallback callback) {
    _onScreenChanged = callback;
    return this;
  }

  /// Register a callback for when a button action is triggered.
  SetgreetFlowCallbacks onActionTriggered(ActionTriggeredCallback callback) {
    _onActionTriggered = callback;
    return this;
  }

  /// Register a callback for when a permission request completes.
  SetgreetFlowCallbacks onPermissionRequested(
      PermissionRequestedCallback callback) {
    _onPermissionRequested = callback;
    return this;
  }

  /// Register a callback for when an error occurs.
  SetgreetFlowCallbacks onError(FlowErrorCallback callback) {
    _onError = callback;
    return this;
  }

  /// Dispatch an event to the appropriate callback.
  void dispatchEvent(SetgreetFlowEvent event) {
    switch (event) {
      case FlowStartedEvent():
        _onStarted?.call(event);
      case FlowCompletedEvent():
        _onCompleted?.call(event);
      case FlowDismissedEvent():
        _onDismissed?.call(event);
      case ScreenChangedEvent():
        _onScreenChanged?.call(event);
      case ActionTriggeredEvent():
        _onActionTriggered?.call(event);
      case PermissionRequestedEvent():
        _onPermissionRequested?.call(event);
      case FlowErrorEvent():
        _onError?.call(event);
    }
  }
}
