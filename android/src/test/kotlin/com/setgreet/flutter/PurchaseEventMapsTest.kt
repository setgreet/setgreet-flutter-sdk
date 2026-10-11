package com.setgreet.flutter

import com.setgreet.listener.SetgreetFlowEvent
import com.setgreet.purchases.SetgreetPurchaseError
import com.setgreet.purchases.SetgreetPurchaseErrorCode
import com.setgreet.purchases.SetgreetRestoreStatus
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The maps the plugin sends on `setgreet/events` for the six purchase events,
 * checked against what `SetgreetFlowEvent.fromMap` (lib/src/flow_events.dart)
 * reads.
 */
class PurchaseEventMapsTest {
  private val plugin = SetgreetPlugin()
  private val timestamp = 1_760_000_000_000L
  private val error = SetgreetPurchaseError(SetgreetPurchaseErrorCode.NETWORK_ERROR, providerCode = null, message = "offline")

  @Test
  fun theSixPurchaseEventMapsCarryTheKeysTheDartParserReads() {
    val common = setOf("type", "flowId", "screenId", "componentId", "provider", "timestamp")
    val maps = listOf(
      Triple(
        "purchaseCompleted",
        plugin.createPurchaseCompletedEvent(
          SetgreetFlowEvent.PurchaseCompleted(
            "flow-1", "screen-1", "buy", "\$rc_annual", "revenuecat", listOf("premium"), timestamp
          )
        ),
        setOf("productRef", "accessRefs")
      ),
      Triple(
        "purchaseCancelled",
        plugin.createPurchaseCancelledEvent(
          SetgreetFlowEvent.PurchaseCancelled("flow-1", "screen-1", "buy", "\$rc_annual", "revenuecat", timestamp)
        ),
        setOf("productRef")
      ),
      Triple(
        "purchaseFailed",
        plugin.createPurchaseFailedEvent(
          SetgreetFlowEvent.PurchaseFailed("flow-1", "screen-1", "buy", "\$rc_annual", "revenuecat", error, timestamp)
        ),
        setOf("productRef", "error")
      ),
      Triple(
        "purchasePending",
        plugin.createPurchasePendingEvent(
          SetgreetFlowEvent.PurchasePending("flow-1", "screen-1", "buy", "\$rc_annual", "revenuecat", timestamp)
        ),
        setOf("productRef")
      ),
      Triple(
        "restoreCompleted",
        plugin.createRestoreCompletedEvent(
          SetgreetFlowEvent.RestoreCompleted(
            "flow-1", "screen-1", "restore", "revenuecat", SetgreetRestoreStatus.NOTHING_TO_RESTORE, emptyList(), timestamp
          )
        ),
        setOf("status", "accessRefs")
      ),
      Triple(
        "restoreFailed",
        plugin.createRestoreFailedEvent(
          SetgreetFlowEvent.RestoreFailed("flow-1", "screen-1", "restore", "revenuecat", error, timestamp)
        ),
        setOf("error")
      )
    )

    for ((type, map, extra) in maps) {
      assertEquals(type, common + extra, map.keys)
      assertEquals(type, map["type"])
      assertEquals(type, "flow-1", map["flowId"])
      assertEquals(type, "screen-1", map["screenId"])
      assertEquals(type, "revenuecat", map["provider"])
      // The Dart parser reads `timestamp` as a num, in milliseconds as on iOS.
      assertEquals(type, 1_760_000_000_000.0, map["timestamp"])
    }

    assertEquals("\$rc_annual", maps[0].second["productRef"])
    assertEquals(listOf("premium"), maps[0].second["accessRefs"])
    assertEquals("buy", maps[0].second["componentId"])
    assertEquals("nothingToRestore", maps[4].second["status"])
    assertEquals(emptyList<String>(), maps[4].second["accessRefs"])
    val errorMap = mapOf("code" to "network_error", "providerCode" to null, "message" to "offline")
    assertEquals(errorMap, maps[2].second["error"])
    assertEquals(errorMap, maps[5].second["error"])
  }
}
