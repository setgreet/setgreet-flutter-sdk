import Flutter
import UIKit
import SetgreetSDK
// Present only when the app opted in with the `setgreet/Lottie` pod.
#if canImport(SetgreetSDKLottie)
import SetgreetSDKLottie
#endif

public class SetgreetPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  /// This engine's purchase bridge. It keeps the `setgreet/purchases`
  /// channel the native proxy provider invokes, for as long as the plugin
  /// instance lives.
  private let purchaseBridge: FlutterPurchaseBridge

  init(purchaseChannel: FlutterMethodChannel) {
    self.purchaseBridge = FlutterPurchaseBridge(channel: purchaseChannel)
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "setgreet", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "setgreet/events", binaryMessenger: registrar.messenger())
    let purchaseChannel = FlutterMethodChannel(name: "setgreet/purchases", binaryMessenger: registrar.messenger())

    let instance = SetgreetPlugin(purchaseChannel: purchaseChannel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
    // Published so the engine calls `detachFromEngine(for:)` on teardown.
    registrar.publish(instance)
  }

  /// A registered provider outlives the engine inside the native SDK: its
  /// waiting calls get their fallback now, so no paywall button stays locked.
  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    purchaseBridge.detach()
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
        .onCustomAction { event in
          self?.sendEvent(self?.createCustomActionEvent(event))
        }
        .onTrackEvent { event in
          self?.sendEvent(self?.createTrackEventEvent(event))
        }
        .onRemindLater { event in
          self?.sendEvent(self?.createRemindLaterEvent(event))
        }
        .onPurchaseCompleted { event in
          self?.sendEvent(self?.createPurchaseCompletedEvent(event))
        }
        .onPurchaseCancelled { event in
          self?.sendEvent(self?.createPurchaseCancelledEvent(event))
        }
        .onPurchaseFailed { event in
          self?.sendEvent(self?.createPurchaseFailedEvent(event))
        }
        .onPurchasePending { event in
          self?.sendEvent(self?.createPurchasePendingEvent(event))
        }
        .onRestoreCompleted { event in
          self?.sendEvent(self?.createRestoreCompletedEvent(event))
        }
        .onRestoreFailed { event in
          self?.sendEvent(self?.createRestoreFailedEvent(event))
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

  // MARK: - Action, error, custom action, track event and remind later
  // (internal, not private: the example's RunnerTests cover them)

  func createActionTriggeredEvent(_ event: ActionTriggeredEvent) -> [String: Any] {
    var dict: [String: Any] = [
      "type": "actionTriggered",
      "flowId": event.flowId,
      "actionType": SetgreetPlugin.canonicalActionType(event.actionType),
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

  func createFlowErrorEvent(_ event: FlowErrorEvent) -> [String: Any] {
    return [
      "type": "flowError",
      "flowId": event.flowId,
      "errorType": errorTypeToString(event.errorType),
      "message": event.message,
      "timestamp": event.timestamp * 1000
    ]
  }

  func createCustomActionEvent(_ event: CustomActionEvent) -> [String: Any] {
    return [
      "type": "customAction",
      "flowId": event.flowId,
      "data": SetgreetPlugin.codecSafe(event.data),
      "screenIndex": event.screenIndex,
      "timestamp": event.timestamp * 1000
    ]
  }

  func createTrackEventEvent(_ event: TrackEventEvent) -> [String: Any] {
    return [
      "type": "trackEvent",
      "flowId": event.flowId,
      "eventName": event.eventName,
      "properties": SetgreetPlugin.codecSafe(event.properties),
      "screenIndex": event.screenIndex,
      "timestamp": event.timestamp * 1000
    ]
  }

  func createRemindLaterEvent(_ event: RemindLaterEvent) -> [String: Any] {
    return [
      "type": "remindLater",
      "flowId": event.flowId,
      "screenIndex": event.screenIndex,
      "timestamp": event.timestamp * 1000
    ]
  }

  /// The canonical snake_case action type ("remind_later") from any spelling
  /// the native SDK uses: "remind_later", "REMIND_LATER" or "remindLater".
  static func canonicalActionType(_ raw: String) -> String {
    var result = ""
    var previous: Character?
    for character in raw {
      if character.isUppercase, let previous = previous, previous.isLowercase || previous.isNumber {
        result.append("_")
      }
      result.append(contentsOf: character.lowercased())
      previous = character
    }
    return result
  }

  /// [value] with only what the standard message codec encodes: an
  /// unsupported value raises an exception when the event is sent. Nil is
  /// NSNull; anything else unsupported becomes its string form.
  static func codecSafe(_ value: Any?) -> Any {
    guard let value = unwrapped(value) else { return NSNull() }
    switch value {
    case is NSNull, is String, is NSNumber:
      return value
    case let dictionary as [AnyHashable: Any]:
      var safe: [String: Any] = [:]
      for (key, item) in dictionary {
        safe[String(describing: key.base)] = codecSafe(item)
      }
      return safe
    case let array as [Any]:
      return array.map { codecSafe($0) }
    default:
      return String(describing: value)
    }
  }

  /// [value] with any `Optional` layers removed; nil for a nil inside them.
  private static func unwrapped(_ value: Any?) -> Any? {
    guard let value = value else { return nil }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    guard let wrapped = mirror.children.first else { return nil }
    return unwrapped(wrapped.value)
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

  // MARK: - Purchase events (internal, not private: the example's RunnerTests cover them)

  func createPurchaseCompletedEvent(_ event: PurchaseCompletedEvent) -> [String: Any] {
    return [
      "type": "purchaseCompleted",
      "flowId": event.flowId,
      "screenId": event.screenId,
      "componentId": event.componentId,
      "productRef": event.productRef,
      "provider": event.provider,
      "accessRefs": event.accessRefs,
      "timestamp": event.timestamp * 1000
    ]
  }

  func createPurchaseCancelledEvent(_ event: PurchaseCancelledEvent) -> [String: Any] {
    return [
      "type": "purchaseCancelled",
      "flowId": event.flowId,
      "screenId": event.screenId,
      "componentId": event.componentId,
      "productRef": event.productRef,
      "provider": event.provider,
      "timestamp": event.timestamp * 1000
    ]
  }

  func createPurchaseFailedEvent(_ event: PurchaseFailedEvent) -> [String: Any] {
    return [
      "type": "purchaseFailed",
      "flowId": event.flowId,
      "screenId": event.screenId,
      "componentId": event.componentId,
      "productRef": event.productRef,
      "provider": event.provider,
      "error": purchaseErrorToDictionary(event.error),
      "timestamp": event.timestamp * 1000
    ]
  }

  func createPurchasePendingEvent(_ event: PurchasePendingEvent) -> [String: Any] {
    return [
      "type": "purchasePending",
      "flowId": event.flowId,
      "screenId": event.screenId,
      "componentId": event.componentId,
      "productRef": event.productRef,
      "provider": event.provider,
      "timestamp": event.timestamp * 1000
    ]
  }

  func createRestoreCompletedEvent(_ event: RestoreCompletedEvent) -> [String: Any] {
    return [
      "type": "restoreCompleted",
      "flowId": event.flowId,
      "screenId": event.screenId,
      "componentId": event.componentId,
      "provider": event.provider,
      "status": event.status.rawValue,
      "accessRefs": event.accessRefs,
      "timestamp": event.timestamp * 1000
    ]
  }

  func createRestoreFailedEvent(_ event: RestoreFailedEvent) -> [String: Any] {
    return [
      "type": "restoreFailed",
      "flowId": event.flowId,
      "screenId": event.screenId,
      "componentId": event.componentId,
      "provider": event.provider,
      "error": purchaseErrorToDictionary(event.error),
      "timestamp": event.timestamp * 1000
    ]
  }

  func purchaseErrorToDictionary(_ error: SetgreetPurchaseError) -> [String: Any] {
    return [
      "code": error.code.rawValue,
      "providerCode": error.providerCode.map { $0 as Any } ?? NSNull(),
      "message": error.message.map { $0 as Any } ?? NSNull()
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
    @unknown default:
      // A reason added in a later SDK: the Dart parser's own fallback.
      return "userClose"
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
    @unknown default:
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
    case "setLocale":
      handleSetLocale(call, result: result)
    case "trackEvent":
      handleTrackEvent(call, result: result)
    case "trackScreen":
      handleTrackScreen(call, result: result)
    case "showFlow":
      handleShowFlow(call, result: result)
    case "getAnonymousId":
      result(Setgreet.shared.anonymousId)
    case "registerLottie":
      result(registerLottie())
    case "setPurchaseProvider":
      handleSetPurchaseProvider(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Registers the optional Lottie component (method calls arrive on the main
  /// thread, where the registry is read). Returns whether Lottie can render:
  /// false when the app did not install the `setgreet/Lottie` pod, in which
  /// case a Lottie component in a flow renders nothing.
  private func registerLottie() -> Bool {
    #if canImport(SetgreetSDKLottie)
    SetgreetLottie.register()
    return true
    #else
    return false
    #endif
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

  /// Saves the device's language choice. Works before `initialize`; nil or
  /// empty clears it, and the native SDK ignores an invalid tag with a warning.
  private func handleSetLocale(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    Setgreet.shared.setLocale(args?["locale"] as? String)
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

  private func handleSetPurchaseProvider(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let providerId = args["providerId"] as? String,
          !providerId.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Provider ID cannot be empty", details: nil))
      return
    }

    let defaultSource = FlutterPurchaseBridge.decodeSource(args["defaultSource"]) ?? .currentOffering
    if args["firstInIsolate"] as? Bool == true {
      // A hot restart: calls still waiting went to the old isolate. Dev only,
      // and not airtight: a call that reached the new isolate after its Dart
      // handler was set but before this registration arrived is answered
      // with the fallback too.
      purchaseBridge.retirePendingCalls()
    }
    Setgreet.shared.setPurchaseProvider(
      FlutterPurchaseProvider(providerId: providerId, bridge: purchaseBridge),
      defaultSource: defaultSource
    )
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
