package com.setgreet.flutter

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.setgreet.Setgreet
import com.setgreet.model.SetgreetConfig

/** SetgreetPlugin */
class SetgreetPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var context: android.content.Context

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "setgreet")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
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
          result.success(null)
        } catch (e: Exception) {
          result.error("INITIALIZATION_ERROR", e.message ?: "Failed to initialize Setgreet SDK", null)
        }
      }
      "identifyUser" -> {
        try {
          val userId = call.argument<String>("userId")
          val attributes = call.argument<Map<String, Any>>("attributes")

          if (userId == null || userId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "User ID cannot be empty", null)
            return
          }

          Setgreet.identifyUser(userId!!, attributes)
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
  }
}
