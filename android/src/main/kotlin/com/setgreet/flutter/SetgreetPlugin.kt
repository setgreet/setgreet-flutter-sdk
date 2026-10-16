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
import com.setgreet.listener.SetgreetFlowListener
import com.setgreet.model.SetgreetConfig
import com.setgreet.purchases.SetgreetPurchaseError
import com.setgreet.purchases.SetgreetPurchaseSource

/** SetgreetPlugin */
class SetgreetPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  private lateinit var channel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private lateinit var context: android.content.Context
  private lateinit var purchaseBridge: FlutterPurchaseBridge
  private var eventSink: EventChannel.EventSink? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "setgreet")
    channel.setMethodCallHandler(this)

    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "setgreet/events")
    eventChannel.setStreamHandler(this)

    context = flutterPluginBinding.applicationContext

    // Per engine: the native proxy provider reaches this engine's Dart
    // purchase provider through it.
    purchaseBridge = FlutterPurchaseBridge(
      FlutterPurchaseChannel(MethodChannel(flutterPluginBinding.binaryMessenger, "setgreet/purchases"))
    )
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
      onPurchaseCompleted { event ->
        sendEvent(createPurchaseCompletedEvent(event))
      }
      onPurchaseCancelled { event ->
        sendEvent(createPurchaseCancelledEvent(event))
      }
      onPurchaseFailed { event ->
        sendEvent(createPurchaseFailedEvent(event))
      }
      onPurchasePending { event ->
        sendEvent(createPurchasePendingEvent(event))
      }
      onRestoreCompleted { event ->
        sendEvent(createRestoreCompletedEvent(event))
      }
      onRestoreFailed { event ->
        sendEvent(createRestoreFailedEvent(event))
      }
    }
    // Custom action, track event and remind later reach only the listener:
    // the callbacks builder has no slot for them. The listener receives every
    // event, so it forwards just these three; the callbacks send the rest.
    // This takes the native SDK's single listener slot: it replaces a host
    // listener set before `initialize`, and a host `setFlowListener` call
    // after it stops these three events in Dart (documented in the README).
    // TODO: once the Android pin moves to 1.8.0, which adds the builder
    // callbacks onCustomAction, onTrackEvent and onRemindLater, switch to
    // those and drop setFlowListener. Never register both, or these events
    // arrive in Dart twice.
    Setgreet.setFlowListener(object : SetgreetFlowListener {
      override fun onFlowEvent(event: SetgreetFlowEvent) {
        listenerOnlyEventMap(event)?.let(::sendEvent)
      }
    })
  }

  /** The map for an event only `setFlowListener` delivers, or null for an event the callbacks already send. */
  internal fun listenerOnlyEventMap(event: SetgreetFlowEvent): Map<String, Any?>? = when (event) {
    is SetgreetFlowEvent.CustomAction -> createCustomActionEvent(event)
    is SetgreetFlowEvent.TrackEvent -> createTrackEventEvent(event)
    is SetgreetFlowEvent.RemindLater -> createRemindLaterEvent(event)
    else -> null
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

  // Internal, not private, for the JVM unit tests (src/test).
  internal fun createActionTriggeredEvent(event: SetgreetFlowEvent.ActionTriggered): Map<String, Any?> {
    return mapOf(
      "type" to "actionTriggered",
      "flowId" to event.flowId,
      // REMIND_LATER -> "remind_later": the canonical snake_case action type.
      // `lowercase()` is locale-invariant, so no Turkish dotless i.
      "actionType" to event.actionType.name.lowercase(),
      "actionName" to event.actionName,
      "screenIndex" to event.screenIndex,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  internal fun createFlowErrorEvent(event: SetgreetFlowEvent.FlowError): Map<String, Any?> {
    return mapOf(
      "type" to "flowError",
      "flowId" to event.flowId,
      "errorType" to event.errorType.toFlutterString(),
      "message" to event.message,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  internal fun createCustomActionEvent(event: SetgreetFlowEvent.CustomAction): Map<String, Any?> {
    return mapOf(
      "type" to "customAction",
      "flowId" to event.flowId,
      "data" to codecSafe(event.data),
      "screenIndex" to event.screenIndex,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  internal fun createTrackEventEvent(event: SetgreetFlowEvent.TrackEvent): Map<String, Any?> {
    return mapOf(
      "type" to "trackEvent",
      "flowId" to event.flowId,
      "eventName" to event.eventName,
      "properties" to codecSafe(event.properties),
      "screenIndex" to event.screenIndex,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  internal fun createRemindLaterEvent(event: SetgreetFlowEvent.RemindLater): Map<String, Any?> {
    return mapOf(
      "type" to "remindLater",
      "flowId" to event.flowId,
      "screenIndex" to event.screenIndex,
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

  // Purchase events: internal, not private, for the JVM unit tests (src/test).

  internal fun createPurchaseCompletedEvent(event: SetgreetFlowEvent.PurchaseCompleted): Map<String, Any?> {
    return mapOf(
      "type" to "purchaseCompleted",
      "flowId" to event.flowId,
      "screenId" to event.screenId,
      "componentId" to event.componentId,
      "productRef" to event.productRef,
      "provider" to event.provider,
      "accessRefs" to event.accessRefs,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  internal fun createPurchaseCancelledEvent(event: SetgreetFlowEvent.PurchaseCancelled): Map<String, Any?> {
    return mapOf(
      "type" to "purchaseCancelled",
      "flowId" to event.flowId,
      "screenId" to event.screenId,
      "componentId" to event.componentId,
      "productRef" to event.productRef,
      "provider" to event.provider,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  internal fun createPurchaseFailedEvent(event: SetgreetFlowEvent.PurchaseFailed): Map<String, Any?> {
    return mapOf(
      "type" to "purchaseFailed",
      "flowId" to event.flowId,
      "screenId" to event.screenId,
      "componentId" to event.componentId,
      "productRef" to event.productRef,
      "provider" to event.provider,
      "error" to event.error.toFlutterMap(),
      "timestamp" to event.timestamp.toDouble()
    )
  }

  internal fun createPurchasePendingEvent(event: SetgreetFlowEvent.PurchasePending): Map<String, Any?> {
    return mapOf(
      "type" to "purchasePending",
      "flowId" to event.flowId,
      "screenId" to event.screenId,
      "componentId" to event.componentId,
      "productRef" to event.productRef,
      "provider" to event.provider,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  internal fun createRestoreCompletedEvent(event: SetgreetFlowEvent.RestoreCompleted): Map<String, Any?> {
    return mapOf(
      "type" to "restoreCompleted",
      "flowId" to event.flowId,
      "screenId" to event.screenId,
      "componentId" to event.componentId,
      "provider" to event.provider,
      "status" to event.status.rawValue,
      "accessRefs" to event.accessRefs,
      "timestamp" to event.timestamp.toDouble()
    )
  }

  internal fun createRestoreFailedEvent(event: SetgreetFlowEvent.RestoreFailed): Map<String, Any?> {
    return mapOf(
      "type" to "restoreFailed",
      "flowId" to event.flowId,
      "screenId" to event.screenId,
      "componentId" to event.componentId,
      "provider" to event.provider,
      "error" to event.error.toFlutterMap(),
      "timestamp" to event.timestamp.toDouble()
    )
  }

  /**
   * [value] with only what the standard message codec encodes: an
   * unsupported value would throw on the main thread when the event is sent.
   * Anything else becomes its string form.
   */
  internal fun codecSafe(value: Any?): Any? = when (value) {
    null, is String, is Boolean, is Int, is Long, is Double -> value
    is Byte, is Short -> value.toInt()
    is Number -> value.toDouble()
    is Map<*, *> -> value.entries.associate { (key, item) -> key.toString() to codecSafe(item) }
    is Iterable<*> -> value.map(::codecSafe)
    is Array<*> -> value.map(::codecSafe)
    else -> value.toString()
  }

  private fun SetgreetPurchaseError.toFlutterMap(): Map<String, Any?> = mapOf(
    "code" to code.rawValue,
    "providerCode" to providerCode,
    "message" to message
  )

  private fun DismissReason.toFlutterString(): String = when (this) {
    DismissReason.USER_CLOSE -> "userClose"
    DismissReason.USER_SKIP -> "userSkip"
    DismissReason.BACK_PRESS -> "backPress"
    DismissReason.REPLACED -> "replaced"
    DismissReason.PROGRAMMATIC -> "programmatic"
    DismissReason.SWIPE_DOWN -> "swipeDown"
    DismissReason.COMPLETED -> "completed"
    DismissReason.REMIND_LATER -> "remindLater"
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
      "getAnonymousId" -> {
        result.success(Setgreet.anonymousId)
      }
      "setPurchaseProvider" -> {
        try {
          val providerId = call.argument<String>("providerId")

          if (providerId == null || providerId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "Provider ID cannot be empty", null)
            return
          }

          val defaultSource = FlutterPurchaseBridge.decodeSource(call.argument<Any>("defaultSource"))
            ?: SetgreetPurchaseSource.currentOffering
          if (call.argument<Boolean>("firstInIsolate") == true) {
            // A hot restart: calls still waiting went to the old isolate. Dev
            // only, and not airtight: a call that reached the new isolate after
            // its Dart handler was set but before this registration arrived is
            // answered with the fallback too.
            purchaseBridge.retirePendingCalls()
          }
          Setgreet.setPurchaseProvider(FlutterPurchaseProvider(providerId, purchaseBridge), defaultSource)
          result.success(null)
        } catch (e: Exception) {
          result.error("PURCHASE_ERROR", e.message ?: "Failed to register the purchase provider", null)
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
    // A registered provider outlives the engine inside the native SDK: its
    // waiting calls get their fallback now, so no paywall button stays locked.
    purchaseBridge.detach()
  }
}
