package com.setgreet.flutter

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.setgreet.Setgreet
import com.setgreet.listener.DismissReason
import com.setgreet.listener.ErrorType
import com.setgreet.listener.SetgreetFlowEvent
import com.setgreet.model.SetgreetConfig

/** SetgreetPlugin */
class SetgreetPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  private lateinit var channel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private lateinit var context: android.content.Context
  private var eventSink: EventChannel.EventSink? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "setgreet")
    channel.setMethodCallHandler(this)

    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "setgreet/events")
    eventChannel.setStreamHandler(this)

    context = flutterPluginBinding.applicationContext
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  private fun setupFlowCallbacks() {
    Setgreet.setFlowCallbacks {
      onFlowStarted { event ->
        sendEvent(createFlowStartedEvent(event))
      }
      onFlowCompleted { event ->
        sendEvent(createFlowCompletedEvent(event))
      }
      onFlowDismissed { event ->
        sendEvent(createFlowDismissedEvent(event))
      }
      onScreenChanged { event ->
        sendEvent(createScreenChangedEvent(event))
      }
      onActionTriggered { event ->
        sendEvent(createActionTriggeredEvent(event))
      }
      onPermissionRequested { event ->
        sendEvent(createPermissionRequestedEvent(event))
      }
      onError { event ->
        sendEvent(createFlowErrorEvent(event))
      }
    }
  }

  private fun sendEvent(data: Map<String, Any?>) {
    android.os.Handler(android.os.Looper.getMainLooper()).post {
      eventSink?.success(data)
    }
  }

  private fun createFlowStartedEvent(event: SetgreetFlowEvent.FlowStarted): Map<String, Any?> {
    return mapOf(
      "type" to "flowStarted",
      "flowId" to event.flowId,
      "screenCount" to event.screenCount,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  private fun createFlowCompletedEvent(event: SetgreetFlowEvent.FlowCompleted): Map<String, Any?> {
    return mapOf(
      "type" to "flowCompleted",
      "flowId" to event.flowId,
      "screenCount" to event.screenCount,
      "durationMs" to event.durationMs,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  private fun createFlowDismissedEvent(event: SetgreetFlowEvent.FlowDismissed): Map<String, Any?> {
    return mapOf(
      "type" to "flowDismissed",
      "flowId" to event.flowId,
      "reason" to event.reason.toFlutterString(),
      "screenIndex" to event.screenIndex,
      "screenCount" to event.screenCount,
      "durationMs" to event.durationMs,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  private fun createScreenChangedEvent(event: SetgreetFlowEvent.ScreenChanged): Map<String, Any?> {
    return mapOf(
      "type" to "screenChanged",
      "flowId" to event.flowId,
      "fromIndex" to event.fromIndex,
      "toIndex" to event.toIndex,
      "screenCount" to event.screenCount,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  private fun createActionTriggeredEvent(event: SetgreetFlowEvent.ActionTriggered): Map<String, Any?> {
    return mapOf(
      "type" to "actionTriggered",
      "flowId" to event.flowId,
      "actionType" to event.actionType.name.lowercase(),
      "actionName" to event.actionName,
      "screenIndex" to event.screenIndex,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  private fun createFlowErrorEvent(event: SetgreetFlowEvent.FlowError): Map<String, Any?> {
    return mapOf(
      "type" to "flowError",
      "flowId" to event.flowId,
      "errorType" to event.errorType.toFlutterString(),
      "message" to event.message,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  private fun createPermissionRequestedEvent(event: SetgreetFlowEvent.PermissionRequested): Map<String, Any?> {
    return mapOf(
      "type" to "permissionRequested",
      "flowId" to event.flowId,
      "permissionType" to event.permissionType,
      "result" to event.result,
      "screenIndex" to event.screenIndex,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  private fun DismissReason.toFlutterString(): String = when (this) {
    DismissReason.USER_CLOSE -> "userClose"
    DismissReason.USER_SKIP -> "userSkip"
    DismissReason.BACK_PRESS -> "backPress"
    DismissReason.REPLACED -> "replaced"
    DismissReason.PROGRAMMATIC -> "programmatic"
  }

  private fun ErrorType.toFlutterString(): String = when (this) {
    ErrorType.NETWORK -> "network"
    ErrorType.PARSE -> "parse"
    ErrorType.DISPLAY -> "display"
    ErrorType.UNKNOWN -> "unknown"
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "initialize" -> {
        try {
          val appKey = call.argument<String>("appKey")
          val debugMode = call.argument<Boolean>("debugMode") ?: false

          if (appKey == null || appKey.isEmpty()) {
            result.error("INVALID_ARGUMENT", "App key cannot be empty", null)
            return
          }

          val config = SetgreetConfig(debugMode = debugMode)
          Setgreet.initialize(context, appKey!!, config)
          setupFlowCallbacks()
          result.success(null)
        } catch (e: Exception) {
          result.error("INITIALIZATION_ERROR", e.message ?: "Failed to initialize Setgreet SDK", null)
        }
      }
      "identifyUser" -> {
        try {
          val userId = call.argument<String>("userId")
          val attributes = call.argument<Map<String, Any>>("attributes")
          val operation = call.argument<String>("operation")
          val locale = call.argument<String>("locale")

          if (userId == null || userId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "User ID cannot be empty", null)
            return
          }

          val op = when (operation?.lowercase()) {
            "update" -> com.setgreet.model.Operation.UPDATE
            else -> com.setgreet.model.Operation.CREATE
          }

          Setgreet.identifyUser(userId!!, attributes, op, locale)
          result.success(null)
        } catch (e: Exception) {
          result.error("USER_ERROR", e.message ?: "Failed to identify user", null)
        }
      }
      "resetUser" -> {
        try {
          Setgreet.resetUser()
          result.success(null)
        } catch (e: Exception) {
          result.error("USER_ERROR", e.message ?: "Failed to reset user", null)
        }
      }
      "trackEvent" -> {
        try {
          val eventName = call.argument<String>("eventName")
          val properties = call.argument<Map<String, Any>>("properties")

          if (eventName == null || eventName.isEmpty()) {
            result.error("INVALID_ARGUMENT", "Event name cannot be empty", null)
            return
          }

          Setgreet.trackEvent(eventName!!, properties)
          result.success(null)
        } catch (e: Exception) {
          result.error("TRACKING_ERROR", e.message ?: "Failed to track event", null)
        }
      }
      "trackScreen" -> {
        try {
          val screenName = call.argument<String>("screenName")
          val properties = call.argument<Map<String, Any>>("properties")

          if (screenName == null || screenName.isEmpty()) {
            result.error("INVALID_ARGUMENT", "Screen name cannot be empty", null)
            return
          }

          Setgreet.trackScreen(screenName!!, properties)
          result.success(null)
        } catch (e: Exception) {
          result.error("TRACKING_ERROR", e.message ?: "Failed to track screen", null)
        }
      }
      "showFlow" -> {
        try {
          val flowId = call.argument<String>("flowId")

          if (flowId == null || flowId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "Flow ID cannot be empty", null)
            return
          }

          Setgreet.showFlow(flowId!!)
          result.success(null)
        } catch (e: Exception) {
          result.error("FLOW_ERROR", e.message ?: "Failed to show flow", null)
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
  }
}
