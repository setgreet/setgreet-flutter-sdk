import Flutter
import UIKit
import SetgreetSDK

public class SetgreetPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "setgreet", binaryMessenger: registrar.messenger())
    let instance = SetgreetPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

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

    Setgreet.shared.initialize(appKey: appKey, config: config)
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

    let op: Operation = (operation?.lowercased() == "update") ? .update : .create

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

    Setgreet.shared.showFlow(flowId: flowId)
    result(nil)
  }
}
