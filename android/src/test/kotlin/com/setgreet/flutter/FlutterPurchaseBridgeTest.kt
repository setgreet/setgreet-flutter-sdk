package com.setgreet.flutter

import com.setgreet.purchases.SetgreetPaywallImpressionContext
import com.setgreet.purchases.SetgreetPurchaseAccessState
import com.setgreet.purchases.SetgreetPurchaseError
import com.setgreet.purchases.SetgreetPurchaseErrorCode
import com.setgreet.purchases.SetgreetPurchaseIntroOffer
import com.setgreet.purchases.SetgreetPurchasePeriod
import com.setgreet.purchases.SetgreetPurchasePeriodUnit
import com.setgreet.purchases.SetgreetPurchaseSource
import com.setgreet.purchases.SetgreetPurchaseStatus
import com.setgreet.purchases.SetgreetRestoreStatus
import java.math.BigDecimal
import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Records what the bridge schedules and lets a test run it. */
private class FakeMainThread : MainThread {
  var onMainThread = true
  val posted = ArrayDeque<Runnable>()
  val delayed = mutableListOf<Pair<Runnable, Long>>()

  override fun isCurrent(): Boolean = onMainThread

  override fun post(task: Runnable) {
    posted.addLast(task)
  }

  override fun postDelayed(task: Runnable, delayMs: Long) {
    delayed += task to delayMs
  }

  override fun cancel(task: Runnable) {
    delayed.removeAll { it.first === task }
  }

  fun runPosted() {
    while (posted.isNotEmpty()) posted.removeFirst().run()
  }

  /** Runs every pending timeout, as if its delay had passed. */
  fun fireTimeouts() {
    val due = delayed.toList()
    delayed.clear()
    due.forEach { it.first.run() }
  }
}

/** Records the bridge's calls; a test answers one through [reply]. */
private class FakeChannel : PurchaseChannel {
  class Call(val method: String, val arguments: Any?, val result: PurchaseChannelResult?)

  val calls = mutableListOf<Call>()

  override fun invokeMethod(method: String, arguments: Any?, result: PurchaseChannelResult?) {
    calls += Call(method, arguments, result)
  }

  fun reply(index: Int): PurchaseChannelResult =
    checkNotNull(calls[index].result) { "call $index (${calls[index].method}) expects no reply" }
}

/**
 * A coroutine started on the test thread with the standard library only and
 * no dispatcher: it runs until it suspends, and resumes on the thread that
 * resumes it, here the test thread. Completing twice fails the test.
 */
private class Started<T> : Continuation<T> {
  override val context: CoroutineContext = EmptyCoroutineContext
  private var outcome: Result<T>? = null

  val isDone: Boolean get() = outcome != null

  override fun resumeWith(result: Result<T>) {
    check(outcome == null) { "the coroutine completed twice" }
    outcome = result
  }

  fun value(): T = checkNotNull(outcome) { "still suspended" }.getOrThrow()

  fun error(): Throwable =
    checkNotNull(outcome) { "still suspended" }.exceptionOrNull() ?: throw AssertionError("completed without an error")
}

private fun <T> start(block: suspend () -> T): Started<T> = Started<T>().also { block.startCoroutine(it) }

class FlutterPurchaseBridgeTest {
  private val mainThread = FakeMainThread()
  private val channel = FakeChannel()
  private val bridge = FlutterPurchaseBridge(channel, mainThread)
  private val source = SetgreetPurchaseSource.offering("discount")
  private val sourceMap = mapOf("sourceType" to "offering", "sourceId" to "discount")

  private fun purchaseError(started: Started<*>): SetgreetPurchaseError = started.error() as SetgreetPurchaseError

  // MARK: - Exactly once

  @Test
  fun accessStateTimesOutOnceAndIgnoresALateReply() {
    val access = start { bridge.accessState() }

    assertEquals(listOf("accessState"), channel.calls.map { it.method })
    assertEquals(listOf(FlutterPurchaseBridge.SAFETY_TIMEOUT_MS), mainThread.delayed.map { it.second })
    assertFalse(access.isDone)

    mainThread.fireTimeouts()
    assertNull(access.value())

    // The Dart side answers after the timeout: the call already resumed.
    channel.reply(0).success(mapOf("active" to true, "accessRefs" to listOf("premium")))
    assertNull(access.value())
  }

  @Test
  fun loadProductsTimeoutMirrorsTheSdksOwnTimeoutError() {
    val load = start { bridge.loadProducts(source) }
    mainThread.fireTimeouts()

    val error = purchaseError(load)
    assertEquals(SetgreetPurchaseErrorCode.NETWORK_ERROR, error.code)
    assertEquals("timeout", error.providerCode)
    assertEquals("loadProducts did not return within 30s", error.message)

    channel.reply(0).success(emptyList<Any>())
  }

  @Test
  fun aReplyCancelsItsTimeout() {
    val access = start { bridge.accessState() }
    channel.reply(0).success(mapOf("active" to false, "accessRefs" to emptyList<String>()))

    assertTrue(mainThread.delayed.isEmpty())
    assertEquals(SetgreetPurchaseAccessState(active = false, accessRefs = emptyList()), access.value())
  }

  @Test
  fun theFirstReplyWinsAnErrorThenSuccessRace() {
    val purchase = start { bridge.purchase("\$rc_annual", source) }
    channel.reply(0).error("error", "boom", null)
    channel.reply(0).success(mapOf("status" to "purchased", "productRef" to "\$rc_annual"))

    val result = purchase.value()
    assertEquals(SetgreetPurchaseStatus.FAILED, result.status)
    assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, result.error?.code)
  }

  @Test
  fun theFirstReplyWinsASuccessThenErrorRace() {
    val restore = start { bridge.restorePurchases() }
    channel.reply(0).success(mapOf("status" to "restored", "accessRefs" to listOf("premium")))
    channel.reply(0).error("error", "late", null)
    channel.reply(0).notImplemented()

    val result = restore.value()
    assertEquals(SetgreetRestoreStatus.RESTORED, result.status)
    assertEquals(listOf("premium"), result.accessRefs)
  }

  @Test
  fun purchaseRestoreIdentifyAndResetHaveNoTimeout() {
    val purchase = start { bridge.purchase("\$rc_annual", source) }
    val restore = start { bridge.restorePurchases() }
    val identify = start { bridge.identify("user-42") }
    val reset = start { bridge.reset() }

    assertTrue(mainThread.delayed.isEmpty())
    assertEquals(listOf("purchase", "restorePurchases", "identify", "reset"), channel.calls.map { it.method })
    assertEquals(mapOf("productRef" to "\$rc_annual", "source" to sourceMap), channel.calls[0].arguments)
    assertNull(channel.calls[1].arguments)
    assertEquals(mapOf("userId" to "user-42"), channel.calls[2].arguments)
    assertFalse(purchase.isDone || restore.isDone || identify.isDone || reset.isDone)

    channel.reply(2).success(null)
    channel.reply(3).success(null)
    assertTrue(identify.isDone && reset.isDone)
  }

  // MARK: - Teardown

  @Test
  fun detachResolvesEveryPendingCall() {
    val purchase = start { bridge.purchase("\$rc_annual", source) }
    val restore = start { bridge.restorePurchases() }
    val load = start { bridge.loadProducts(source) }
    val access = start { bridge.accessState() }
    val identify = start { bridge.identify("user-42") }
    val reset = start { bridge.reset() }

    bridge.detach()

    purchase.value().let {
      assertEquals(SetgreetPurchaseStatus.FAILED, it.status)
      assertEquals("\$rc_annual", it.productRef)
      assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, it.error?.code)
      assertEquals("flutter_engine_detached", it.error?.providerCode)
    }
    restore.value().let {
      assertEquals(SetgreetRestoreStatus.FAILED, it.status)
      assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, it.error?.code)
    }
    assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, purchaseError(load).code)
    assertNull(access.value())
    identify.value()
    reset.value()
    assertTrue("the timeouts were cancelled", mainThread.delayed.isEmpty())

    // Late replies to the dead engine's calls are dropped.
    channel.calls.forEach { it.result?.notImplemented() }

    // Later calls end at once and send nothing.
    val later = start { bridge.purchase("\$rc_monthly", source) }
    assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, later.value().error?.code)
    bridge.send("setAttributes", mapOf("attributes" to mapOf("setgreet_flow" to "flow-1")))
    assertEquals(6, channel.calls.size)
  }

  @Test
  fun aHotRestartRetiresTheCallsTheOldIsolateNeverAnswers() {
    val purchase = start { bridge.purchase("\$rc_annual", source) }
    val identify = start { bridge.identify("user-42") }

    bridge.retirePendingCalls()

    purchase.value().let {
      assertEquals(SetgreetPurchaseStatus.FAILED, it.status)
      assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, it.error?.code)
      assertEquals("flutter_provider_unavailable", it.error?.providerCode)
    }
    assertTrue(identify.isDone)

    // The channel still serves the new isolate.
    val restore = start { bridge.restorePurchases() }
    channel.reply(2).success(
      mapOf("status" to "nothingToRestore", "accessRefs" to emptyList<String>(), "error" to null)
    )
    assertEquals(SetgreetRestoreStatus.NOTHING_TO_RESTORE, restore.value().status)
  }

  // MARK: - No usable Dart provider, error replies

  @Test
  fun notImplementedMeansNoProvider() {
    val purchase = start { bridge.purchase("\$rc_annual", source) }
    val restore = start { bridge.restorePurchases() }
    val load = start { bridge.loadProducts(source) }
    val access = start { bridge.accessState() }
    channel.calls.forEach { it.result?.notImplemented() }

    assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, purchase.value().error?.code)
    assertEquals("flutter_provider_unavailable", purchase.value().error?.providerCode)
    assertEquals(SetgreetRestoreStatus.FAILED, restore.value().status)
    assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, restore.value().error?.code)
    assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, purchaseError(load).code)
    assertNull(access.value())
  }

  @Test
  fun anErrorReplyToAPurchaseOrRestoreMeansTheBridgeFailed() {
    val purchase = start { bridge.purchase("\$rc_annual", source) }
    val restore = start { bridge.restorePurchases() }
    channel.reply(0).error("error", "boom", null)
    channel.reply(1).error("network_error", "offline", mapOf("providerCode" to "NetworkError"))

    assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, purchase.value().error?.code)
    assertEquals("flutter_provider_unavailable", purchase.value().error?.providerCode)
    assertEquals(SetgreetRestoreStatus.FAILED, restore.value().status)
    assertEquals(SetgreetPurchaseErrorCode.NOT_CONFIGURED, restore.value().error?.code)
  }

  @Test
  fun aLoadProductsErrorReplyKeepsTheProvidersCode() {
    val load = start { bridge.loadProducts(source) }
    channel.reply(0).error("network_error", "offline", mapOf("providerCode" to "NetworkError"))

    val error = purchaseError(load)
    assertEquals(SetgreetPurchaseErrorCode.NETWORK_ERROR, error.code)
    assertEquals("NetworkError", error.providerCode)
    assertEquals("offline", error.message)
  }

  @Test
  fun aGenericFlutterErrorFromLoadProductsIsUnknown() {
    val load = start { bridge.loadProducts(source) }
    channel.reply(0).error("error", "a Dart exception", null)

    assertEquals(SetgreetPurchaseErrorCode.UNKNOWN, purchaseError(load).code)
  }

  @Test
  fun anAccessStateErrorReplyIsNull() {
    val access = start { bridge.accessState() }
    channel.reply(0).error("error", "boom", null)

    assertNull(access.value())
  }

  // MARK: - Threading

  @Test
  fun callsFromAnotherThreadArePostedToTheMainThread() {
    mainThread.onMainThread = false
    val access = start { bridge.accessState() }
    bridge.send("setAttributes", mapOf("attributes" to mapOf("setgreet_flow" to "flow-1")))
    assertTrue(channel.calls.isEmpty())

    mainThread.runPosted()
    assertEquals(listOf("accessState", "setAttributes"), channel.calls.map { it.method })
    assertNull("fire-and-forget: nobody waits", channel.calls[1].result)

    channel.reply(0).success(null)
    assertNull(access.value())
  }

  // MARK: - Decoding

  private fun product(
    ref: String?,
    priceAmount: Any?,
    title: String? = null,
    description: String? = null,
    period: Map<String, Any?>? = null,
    introOffer: Map<String, Any?>? = null
  ): Map<String, Any?> = buildMap {
    if (ref != null) put("ref", ref)
    put("storeProductId", "com.app.${ref ?: "missing"}")
    put("title", title)
    put("description", description)
    put("localizedPrice", "\$$priceAmount")
    put("priceAmount", priceAmount)
    put("currencyCode", "USD")
    put("period", period)
    put("introOffer", introOffer)
  }

  @Test
  fun decodesProductsFromPlainMapsKeepingExactPrices() {
    val load = start { bridge.loadProducts(source) }
    assertEquals(mapOf("source" to sourceMap), channel.calls[0].arguments)

    // StandardMessageCodec hands Dart doubles over as Double and Dart ints as
    // Int or Long, depending on their size.
    channel.reply(0).success(
      listOf(
        product(
          "\$rc_annual", 49.99,
          title = "Premium Annual",
          description = "Full access",
          period = mapOf("unit" to "year", "count" to 1),
          introOffer = mapOf("type" to "trial", "localizedPrice" to "\$0.00", "periodText" to "7 days", "eligible" to true)
        ),
        product("\$rc_weekly", 0.99, period = mapOf("unit" to "week", "count" to 1L)),
        product("lifetime_int", 1299),
        product("lifetime_long", 1299L),
        product("lifetime_double", 1299.0),
        product(null, 1.99),
        product("not_a_number", Double.NaN),
        product("no_price", null)
      )
    )

    val products = load.value()
    assertEquals(
      listOf("\$rc_annual", "\$rc_weekly", "lifetime_int", "lifetime_long", "lifetime_double"),
      products.map { it.ref }
    )
    assertEquals(BigDecimal("49.99"), products[0].priceAmount)
    assertEquals("49.99", products[0].priceAmount.toPlainString())
    assertEquals(BigDecimal("0.99"), products[1].priceAmount)
    assertEquals(BigDecimal("1299"), products[2].priceAmount)
    assertEquals(BigDecimal("1299"), products[3].priceAmount)
    assertEquals(0, BigDecimal("1299").compareTo(products[4].priceAmount))

    val annual = products[0]
    assertEquals("com.app.\$rc_annual", annual.storeProductId)
    assertEquals("Premium Annual", annual.title)
    assertEquals("Full access", annual.description)
    assertEquals("\$49.99", annual.localizedPrice)
    assertEquals("USD", annual.currencyCode)
    assertEquals(SetgreetPurchasePeriod(SetgreetPurchasePeriodUnit.YEAR, 1), annual.period)
    assertEquals(SetgreetPurchaseIntroOffer("trial", "\$0.00", "7 days", true), annual.introOffer)
    assertEquals(SetgreetPurchasePeriod(SetgreetPurchasePeriodUnit.WEEK, 1), products[1].period)

    val lifetime = products[2]
    assertNull(lifetime.title)
    assertNull(lifetime.description)
    assertNull(lifetime.period)
    assertNull(lifetime.introOffer)
  }

  @Test
  fun decimalGoesThroughTheShortestDecimalString() {
    assertEquals(BigDecimal("49.99"), FlutterPurchaseBridge.decimal(49.99))
    assertEquals(BigDecimal("0.99"), FlutterPurchaseBridge.decimal(0.99))
    assertEquals(BigDecimal("1299"), FlutterPurchaseBridge.decimal(1299))
    assertEquals(BigDecimal("1299"), FlutterPurchaseBridge.decimal(1299L))
    assertEquals(BigDecimal("12.50"), FlutterPurchaseBridge.decimal("12.50"))
    assertNull(FlutterPurchaseBridge.decimal(Double.POSITIVE_INFINITY))
    assertNull(FlutterPurchaseBridge.decimal(Double.NaN))
    assertNull(FlutterPurchaseBridge.decimal("free"))
    assertNull(FlutterPurchaseBridge.decimal(true))
    assertNull(FlutterPurchaseBridge.decimal(null))
  }

  @Test
  fun unknownStatusesAreFailedAndMissingFieldsAreCoerced() {
    val purchase = start { bridge.purchase("\$rc_annual", source) }
    val restore = start { bridge.restorePurchases() }
    val access = start { bridge.accessState() }
    val pending = start { bridge.purchase("\$rc_monthly", source) }

    channel.reply(0).success(mapOf("status" to "bogus", "productRef" to "\$rc_annual"))
    channel.reply(1).success(mapOf("status" to "partial", "accessRefs" to "premium"))
    channel.reply(2).success(mapOf("accessRefs" to listOf("premium")))
    channel.reply(3).success(
      mapOf(
        "status" to "pending",
        "error" to mapOf("code" to "purchase_pending", "providerCode" to "paymentPendingError", "message" to null)
      )
    )

    purchase.value().let {
      assertEquals(SetgreetPurchaseStatus.FAILED, it.status)
      assertEquals(SetgreetPurchaseErrorCode.UNKNOWN, it.error?.code)
    }
    restore.value().let {
      assertEquals(SetgreetRestoreStatus.FAILED, it.status)
      assertEquals(SetgreetPurchaseErrorCode.UNKNOWN, it.error?.code)
      assertEquals(emptyList<String>(), it.accessRefs)
    }
    assertNull("no `active`: cannot say", access.value())
    pending.value().let {
      assertEquals(SetgreetPurchaseStatus.PENDING, it.status)
      assertEquals("a missing productRef is the requested one", "\$rc_monthly", it.productRef)
      assertEquals(emptyList<String>(), it.accessRefs)
      assertEquals(SetgreetPurchaseErrorCode.PURCHASE_PENDING, it.error?.code)
      assertEquals("paymentPendingError", it.error?.providerCode)
    }
  }

  @Test
  fun decodesSourcesAndEncodesImpressions() {
    assertEquals(
      SetgreetPurchaseSource.placement("onboarding"),
      FlutterPurchaseBridge.decodeSource(mapOf("sourceType" to "placement", "sourceId" to "onboarding"))
    )
    assertEquals(
      SetgreetPurchaseSource.currentOffering,
      FlutterPurchaseBridge.decodeSource(mapOf("sourceType" to "current_offering", "sourceId" to null))
    )
    assertNull(FlutterPurchaseBridge.decodeSource(mapOf("sourceId" to "onboarding")))
    assertNull(FlutterPurchaseBridge.decodeSource("current_offering"))

    assertEquals(
      mapOf(
        "flowId" to "flow-1",
        "screenId" to "screen-1",
        "source" to sourceMap,
        "productRefs" to listOf("\$rc_annual")
      ),
      FlutterPurchaseBridge.encodeImpression(
        SetgreetPaywallImpressionContext("flow-1", "screen-1", source, listOf("\$rc_annual"))
      )
    )
  }

  // MARK: - The provider proxy

  @Test
  fun theProviderSendsImpressionsAndAttributesWithoutWaiting() {
    val provider = FlutterPurchaseProvider("revenuecat", bridge)
    assertEquals("revenuecat", provider.providerId)

    provider.trackPaywallImpression(
      SetgreetPaywallImpressionContext("flow-1", "screen-1", source, listOf("\$rc_annual"))
    )
    provider.setAttributes(mapOf("setgreet_flow" to "flow-1"))

    assertEquals(listOf("trackPaywallImpression", "setAttributes"), channel.calls.map { it.method })
    assertTrue(channel.calls.all { it.result == null })
    assertEquals(mapOf("attributes" to mapOf("setgreet_flow" to "flow-1")), channel.calls[1].arguments)
  }
}
