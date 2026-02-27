import Flutter
import UIKit
import SetgreetSDK

public class SetgreetPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "setgreet", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "setgreet/events", binaryMessenger: registrar.messenger())

    let instance = SetgreetPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
  }

  // MARK: - FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // MARK: - Flow Callbacks

  private func setupFlowCallbacks() {
    Setgreet.shared.setFlowCallbacks { [weak self] callbacks in
      callbacks
        .onFlowStarted { event in
          self?.sendEvent(self?.createFlowStartedEvent(event))
        }
        .onFlowCompleted { event in
          self?.sendEvent(self?.createFlowCompletedEvent(event))
        }
        .onFlowDismissed { event in
          self?.sendEvent(self?.createFlowDismissedEvent(event))
        }
        .onScreenChanged { event in
          self?.sendEvent(self?.createScreenChangedEvent(event))
        }
        .onActionTriggered { event in
          self?.sendEvent(self?.createActionTriggeredEvent(event))
        }
        .onPermissionRequested { event in
          self?.sendEvent(self?.createPermissionRequestedEvent(event))
        }
        .onError { event in
          self?.sendEvent(self?.createFlowErrorEvent(event))
        }
    }
  }

  private func sendEvent(_ data: [String: Any]?) {
    guard let data = data, let eventSink = eventSink else { return }
    DispatchQueue.main.async {
      eventSink(data)
    }
  }

  private func createFlowStartedEvent(_ event: FlowStartedEvent) -> [String: Any] {
    return [
      "type": "flowStarted",
      "flowId": event.flowId,
      "screenCount": event.screenCount,
      "timestamp": event.timestamp * 1000
    ]
  }

  private func createFlowCompletedEvent(_ event: FlowCompletedEvent) -> [String: Any] {
    return [
      "type": "flowCompleted",
      "flowId": event.flowId,
      "screenCount": event.screenCount,
      "durationMs": event.durationMs,
      "timestamp": event.timestamp * 1000
    ]
  }

  private func createFlowDismissedEvent(_ event: FlowDismissedEvent) -> [String: Any] {
    return [
      "type": "flowDismissed",
      "flowId": event.flowId,
      "reason": dismissReasonToString(event.reason),
      "screenIndex": event.screenIndex,
      "screenCount": event.screenCount,
      "durationMs": event.durationMs,
      "timestamp": event.timestamp * 1000
    ]
  }

  private func createScreenChangedEvent(_ event: ScreenChangedEvent) -> [String: Any] {
    return [
      "type": "screenChanged",
      "flowId": event.flowId,
      "fromIndex": event.fromIndex,
      "toIndex": event.toIndex,
      "screenCount": event.screenCount,
      "timestamp": event.timestamp * 1000
    ]
  }

  private func createActionTriggeredEvent(_ event: ActionTriggeredEvent) -> [String: Any] {
    var dict: [String: Any] = [
      "type": "actionTriggered",
      "flowId": event.flowId,
      "actionType": event.actionType.lowercased(),
      "screenIndex": event.screenIndex,
      "timestamp": event.timestamp * 1000
    ]
    if let actionName = event.actionName {
      dict["actionName"] = actionName
    } else {
      dict["actionName"] = NSNull()
    }
    return dict
  }

  private func createFlowErrorEvent(_ event: FlowErrorEvent) -> [String: Any] {
    return [
      "type": "flowError",
      "flowId": event.flowId,
      "errorType": errorTypeToString(event.errorType),
      "message": event.message,
      "timestamp": event.timestamp * 1000
    ]
  }

  private func createPermissionRequestedEvent(_ event: PermissionRequestedEvent) -> [String: Any] {
    return [
      "type": "permissionRequested",
      "flowId": event.flowId,
      "permissionType": permissionTypeToString(event.permissionType),
      "result": permissionResultToString(event.result),
      "screenIndex": event.screenIndex,
      "timestamp": event.timestamp * 1000
    ]
  }

  private func dismissReasonToString(_ reason: DismissReason) -> String {
    switch reason {
    case .userClose:
      return "userClose"
    case .userSkip:
      return "userSkip"
    case .backPress:
      return "backPress"
    case .replaced:
      return "replaced"
    case .programmatic:
      return "programmatic"
    case .swipeDown:
      return "swipeDown"
    case .completed:
      return "completed"
    case .remindLater:
      return "remindLater"
    }
  }

  private func errorTypeToString(_ errorType: FlowErrorType) -> String {
    switch errorType {
    case .network:
      return "network"
    case .parse:
      return "parse"
    case .display:
      return "display"
    case .unknown:
      return "unknown"
    }
  }

  private func permissionTypeToString(_ permissionType: String) -> String {
    return permissionType
  }

  private func permissionResultToString(_ result: String) -> String {
    return result
  }

  // MARK: - Method Handling

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      handleInitialize(call, result: result)
    case "identifyUser":
      handleIdentifyUser(call, result: result)
    case "resetUser":
      handleResetUser(call, result: result)
    case "trackEvent":
      handleTrackEvent(call, result: result)
    case "trackScreen":
      handleTrackScreen(call, result: result)
    case "showFlow":
      handleShowFlow(call, result: result)
    case "getAnonymousId":
      result(Setgreet.shared.anonymousId)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleInitialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let appKey = args["appKey"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "App key is required", details: nil))
      return
    }

    if appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "App key cannot be empty", details: nil))
      return
    }

    let debugMode = args["debugMode"] as? Bool ?? false
    let config = SetgreetConfig(debugMode: debugMode)

    DispatchQueue.main.async { [weak self] in
      Setgreet.shared.initialize(appKey: appKey, config: config)
      self?.setupFlowCallbacks()
    }
    result(nil)
  }

  private func handleIdentifyUser(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let userId = args["userId"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "User ID is required", details: nil))
      return
    }

    if userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "User ID cannot be empty", details: nil))
      return
    }

    let attributes = args["attributes"] as? [String: Any]
    let operation = args["operation"] as? String
    let locale = args["locale"] as? String

    let op: SetgreetSDK.Operation = (operation?.lowercased() == "update") ? .update : .create

    Setgreet.shared.identifyUser(
      userId: userId,
      attributes: attributes,
      operation: op,
      locale: locale
    )
    result(nil)
  }

  private func handleResetUser(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    Setgreet.shared.resetUser()
    result(nil)
  }

  private func handleTrackEvent(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let eventName = args["eventName"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Event name is required", details: nil))
      return
    }

    if eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Event name cannot be empty", details: nil))
      return
    }

    let properties = args["properties"] as? [String: Any]
    Setgreet.shared.trackEvent(eventName: eventName, properties: properties)
    result(nil)
  }

  private func handleTrackScreen(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let screenName = args["screenName"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Screen name is required", details: nil))
      return
    }

    if screenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Screen name cannot be empty", details: nil))
      return
    }

    let properties = args["properties"] as? [String: Any]
    Setgreet.shared.trackScreen(screenName: screenName, properties: properties)
    result(nil)
  }

  private func handleShowFlow(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let flowId = args["flowId"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Flow ID is required", details: nil))
      return
    }

    if flowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Flow ID cannot be empty", details: nil))
      return
    }

    DispatchQueue.main.async {
      Setgreet.shared.showFlow(flowId: flowId)
    }
    result(nil)
  }
}
