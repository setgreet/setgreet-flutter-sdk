package com.setgreet.flutter

import com.setgreet.domain.model.flow.ActionType
import com.setgreet.listener.ErrorType
import com.setgreet.listener.SetgreetFlowEvent
import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The maps the plugin sends on `setgreet/events` for action triggered, flow
 * error, custom action, track event and remind later, checked against what
 * `SetgreetFlowEvent.fromMap` (lib/src/flow_events.dart) reads.
 */
class FlowEventMapsTest {
  private val plugin = SetgreetPlugin()
  private val timestamp = 1_760_000_000_000L

  @Test
  fun everyActionTypeReachesDartAsItsCanonicalSnakeCaseString() {
    val canonical = listOf(
      "next", "previous", "skip", "dismiss", "remind_later", "url", "deeplink",
      "request_notification_permission", "request_location_permission",
      "request_camera_permission", "request_tracking_permission",
      "request_microphone_permission", "request_photo_library_permission",
      "request_review", "share", "open_settings", "track_event", "custom",
      "purchase", "restore_purchases"
    )

    val sent = ActionType.values()
      .filter { it != ActionType.NONE }
      .map { actionType ->
        plugin.createActionTriggeredEvent(
          SetgreetFlowEvent.ActionTriggered("flow-1", actionType, null, 2, timestamp)
        )["actionType"]
      }

    assertEquals(canonical, sent)
  }

  @Test
  fun actionTriggeredCarriesTheKeysTheDartParserReads() {
    val map = plugin.createActionTriggeredEvent(
      SetgreetFlowEvent.ActionTriggered("flow-1", ActionType.TRACK_EVENT, "plan_viewed", 2, timestamp)
    )

    assertEquals(
      mapOf(
        "type" to "actionTriggered",
        "flowId" to "flow-1",
        "actionType" to "track_event",
        "actionName" to "plan_viewed",
        "screenIndex" to 2,
        "timestamp" to 1_760_000_000_000.0
      ),
      map
    )
  }

  @Test
  fun everyErrorTypeMapsToTheDartWireValue() {
    val sent = ErrorType.values().associateWith { errorType ->
      plugin.createFlowErrorEvent(SetgreetFlowEvent.FlowError("flow-1", errorType, "boom", timestamp))
    }

    assertEquals("network", sent.getValue(ErrorType.NETWORK)["errorType"])
    assertEquals("parse", sent.getValue(ErrorType.PARSE)["errorType"])
    assertEquals("display", sent.getValue(ErrorType.DISPLAY)["errorType"])
    assertEquals("unknown", sent.getValue(ErrorType.UNKNOWN)["errorType"])
    for (map in sent.values) {
      assertEquals(setOf("type", "flowId", "errorType", "message", "timestamp"), map.keys)
      assertEquals("flowError", map["type"])
      assertEquals("boom", map["message"])
    }
  }

  @Test
  fun theListenerForwardsOnlyTheThreeEventsTheCallbacksCannotReceive() {
    val customAction = plugin.listenerOnlyEventMap(
      SetgreetFlowEvent.CustomAction("flow-1", mapOf("screen" to "paywall", "missing" to null), 1, timestamp)
    )
    assertEquals(
      mapOf(
        "type" to "customAction",
        "flowId" to "flow-1",
        "data" to mapOf("screen" to "paywall", "missing" to null),
        "screenIndex" to 1,
        "timestamp" to 1_760_000_000_000.0
      ),
      customAction
    )

    val trackEvent = plugin.listenerOnlyEventMap(
      SetgreetFlowEvent.TrackEvent("flow-1", "plan_viewed", mapOf("plan" to "annual"), 1, timestamp)
    )
    assertEquals(
      mapOf(
        "type" to "trackEvent",
        "flowId" to "flow-1",
        "eventName" to "plan_viewed",
        "properties" to mapOf("plan" to "annual"),
        "screenIndex" to 1,
        "timestamp" to 1_760_000_000_000.0
      ),
      trackEvent
    )

    val remindLater = plugin.listenerOnlyEventMap(SetgreetFlowEvent.RemindLater("flow-1", 3, timestamp))
    assertEquals(
      mapOf("type" to "remindLater", "flowId" to "flow-1", "screenIndex" to 3, "timestamp" to 1_760_000_000_000.0),
      remindLater
    )

    // The callbacks already send these: forwarding them here would send them twice.
    assertNull(plugin.listenerOnlyEventMap(SetgreetFlowEvent.FlowStarted("flow-1", 3, timestamp)))
    assertNull(
      plugin.listenerOnlyEventMap(
        SetgreetFlowEvent.ActionTriggered("flow-1", ActionType.CUSTOM, null, 1, timestamp)
      )
    )
    assertNull(
      plugin.listenerOnlyEventMap(SetgreetFlowEvent.FlowError("flow-1", ErrorType.NETWORK, "offline", timestamp))
    )
  }

  @Test
  fun absentDataAndPropertiesAreNull() {
    assertNull(plugin.createCustomActionEvent(SetgreetFlowEvent.CustomAction("flow-1", null, 0, timestamp))["data"])
    assertNull(
      plugin.createTrackEventEvent(SetgreetFlowEvent.TrackEvent("flow-1", "e", null, 0, timestamp))["properties"]
    )
  }

  @Test
  fun valuesTheMessageCodecCannotEncodeAreConverted() {
    class Opaque {
      override fun toString() = "opaque"
    }

    val safe = plugin.codecSafe(
      mapOf(
        "string" to "s",
        "int" to 1,
        "long" to 2L,
        "double" to 1.5,
        "bool" to true,
        "short" to 3.toShort(),
        "float" to 2.5f,
        "decimal" to BigDecimal("4.25"),
        "list" to listOf(Opaque(), mapOf(7 to "seven")),
        "array" to arrayOf("a", null),
        "opaque" to Opaque()
      )
    )

    assertEquals(
      mapOf(
        "string" to "s",
        "int" to 1,
        "long" to 2L,
        "double" to 1.5,
        "bool" to true,
        "short" to 3,
        "float" to 2.5,
        "decimal" to 4.25,
        "list" to listOf("opaque", mapOf("7" to "seven")),
        "array" to listOf("a", null),
        "opaque" to "opaque"
      ),
      safe
    )
  }
}
