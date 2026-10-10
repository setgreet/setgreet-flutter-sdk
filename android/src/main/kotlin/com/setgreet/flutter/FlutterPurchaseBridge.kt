package com.setgreet.flutter

import android.app.Activity
import android.os.Handler
import android.os.Looper
import com.setgreet.purchases.SetgreetPaywallImpressionContext
import com.setgreet.purchases.SetgreetPurchaseAccessState
import com.setgreet.purchases.SetgreetPurchaseError
import com.setgreet.purchases.SetgreetPurchaseErrorCode
import com.setgreet.purchases.SetgreetPurchaseIntroOffer
import com.setgreet.purchases.SetgreetPurchasePeriod
import com.setgreet.purchases.SetgreetPurchasePeriodUnit
import com.setgreet.purchases.SetgreetPurchaseProduct
import com.setgreet.purchases.SetgreetPurchaseProvider
import com.setgreet.purchases.SetgreetPurchaseResult
import com.setgreet.purchases.SetgreetPurchaseSource
import com.setgreet.purchases.SetgreetPurchaseStatus
import com.setgreet.purchases.SetgreetRestoreResult
import com.setgreet.purchases.SetgreetRestoreStatus
import io.flutter.plugin.common.MethodChannel
import java.math.BigDecimal
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/**
 * The native end of the purchase bridge, one per Flutter engine.
 *
 * The SDK calls a native [SetgreetPurchaseProvider]; in a Flutter app the
 * host's provider is a Dart object. [FlutterPurchaseProvider] is the native
 * provider registered with `Setgreet.setPurchaseProvider`: each of its
 * methods invokes `setgreet/purchases` on the main thread, and the Dart
 * handler answers from the registered Dart provider (protocol:
 * `lib/src/purchase_bridge.dart`).
 *
 * Every call resumes exactly once. Without a usable Dart provider (no
 * handler or "not implemented", the engine detached, or an old isolate after
 * a hot restart), `purchase` and `restorePurchases` report `FAILED` with
 * `NOT_CONFIGURED`, `loadProducts` throws `NOT_CONFIGURED`, `accessState` is
 * null, and `identify` / `reset` return. An error reply depends on the
 * method: for `loadProducts` it is the Dart provider's own error and keeps
 * its code (a generic Flutter error, with no contract code, becomes
 * `UNKNOWN`); the Dart side answers `purchase` and `restorePurchases` with a
 * result even when the provider throws, so an error reply there means the
 * bridge itself failed and reports `NOT_CONFIGURED`; `accessState` is null.
 *
 * Timeouts: `loadProducts` and `accessState` give up after
 * [SAFETY_TIMEOUT_MS], longer than the SDK's own 10 s, so a Dart provider
 * that never answers cannot hold a call forever (`loadProducts` then throws
 * `NETWORK_ERROR` with `providerCode` "timeout", as the SDK's own timeout
 * does). `purchase` and `restorePurchases` have none: a store sheet can stay
 * open for minutes. Neither have `identify` and `reset`: the SDK runs them
 * one after another and writes the access attributes once they are done, so
 * cutting a slow `logIn` short could write the previous user's access onto
 * the new one. The engine teardown still resolves all of them.
 *
 * Built on the Kotlin standard library's coroutine primitives only:
 * kotlinx.coroutines is not on this plugin's compile classpath (the native
 * SDK keeps it an `implementation` dependency).
 */
internal class FlutterPurchaseBridge(channel: MethodChannel) {

  private sealed class Reply {
    class Success(val value: Any?) : Reply()
    class Failure(val code: String, val message: String?, val details: Any?) : Reply()
    class Unavailable(val reason: String, val providerCode: String) : Reply()
    object TimedOut : Reply()
  }

  private val mainHandler = Handler(Looper.getMainLooper())
  private val lock = Any()

  /** Null once the engine is detached. Guarded by [lock]. */
  private var channel: MethodChannel? = channel

  /** Calls waiting for a Dart reply. Guarded by [lock]. */
  private val pending = LinkedHashSet<PendingCall>()

  // MARK: - Provider calls

  suspend fun loadProducts(source: SetgreetPurchaseSource): List<SetgreetPurchaseProduct> =
    when (val reply = call("loadProducts", mapOf("source" to encodeSource(source)), SAFETY_TIMEOUT_MS)) {
      is Reply.Success -> decodeProducts(reply.value)
      // The Dart provider threw: its error, as the bridge encoded it.
      is Reply.Failure -> throw purchaseError(reply)
      is Reply.Unavailable -> throw SetgreetPurchaseError(
        SetgreetPurchaseErrorCode.NOT_CONFIGURED,
        providerCode = reply.providerCode,
        message = reply.reason
      )
      Reply.TimedOut -> throw SetgreetPurchaseError(
        SetgreetPurchaseErrorCode.NETWORK_ERROR,
        providerCode = "timeout",
        message = "loadProducts did not return within ${SAFETY_TIMEOUT_MS / 1000}s"
      )
    }

  suspend fun purchase(productRef: String, source: SetgreetPurchaseSource): SetgreetPurchaseResult {
    val arguments = mapOf("productRef" to productRef, "source" to encodeSource(source))
    return when (val reply = call("purchase", arguments, timeoutMs = null)) {
      is Reply.Success -> decodePurchaseResult(reply.value, productRef)
      is Reply.Failure -> SetgreetPurchaseResult(SetgreetPurchaseStatus.FAILED, productRef, error = notConfigured(reply))
      is Reply.Unavailable -> SetgreetPurchaseResult(
        SetgreetPurchaseStatus.FAILED,
        productRef,
        error = SetgreetPurchaseError(SetgreetPurchaseErrorCode.NOT_CONFIGURED, reply.providerCode, reply.reason)
      )
      // No timeout is set for a purchase.
      Reply.TimedOut -> SetgreetPurchaseResult(
        SetgreetPurchaseStatus.FAILED,
        productRef,
        error = SetgreetPurchaseError(SetgreetPurchaseErrorCode.UNKNOWN)
      )
    }
  }

  suspend fun restorePurchases(): SetgreetRestoreResult =
    when (val reply = call("restorePurchases", null, timeoutMs = null)) {
      is Reply.Success -> decodeRestoreResult(reply.value)
      is Reply.Failure -> SetgreetRestoreResult(SetgreetRestoreStatus.FAILED, error = notConfigured(reply))
      is Reply.Unavailable -> SetgreetRestoreResult(
        SetgreetRestoreStatus.FAILED,
        error = SetgreetPurchaseError(SetgreetPurchaseErrorCode.NOT_CONFIGURED, reply.providerCode, reply.reason)
      )
      // No timeout is set for a restore.
      Reply.TimedOut -> SetgreetRestoreResult(
        SetgreetRestoreStatus.FAILED,
        error = SetgreetPurchaseError(SetgreetPurchaseErrorCode.UNKNOWN)
      )
    }

  suspend fun accessState(): SetgreetPurchaseAccessState? =
    when (val reply = call("accessState", null, SAFETY_TIMEOUT_MS)) {
      is Reply.Success -> decodeAccessState(reply.value)
      else -> null
    }

  suspend fun identify(userId: String) {
    call("identify", mapOf("userId" to userId), timeoutMs = null)
  }

  suspend fun reset() {
    call("reset", null, timeoutMs = null)
  }

  /** Fire-and-forget: the SDK does not wait for these. */
  fun send(method: String, arguments: Any?) {
    runOnMain {
      val channel = synchronized(lock) { channel } ?: return@runOnMain
      try {
        channel.invokeMethod(method, arguments)
      } catch (e: Exception) {
        // The engine is going away; nothing is waiting for this call.
      }
    }
  }

  // MARK: - Lifecycle

  /**
   * The engine is detached: every waiting call gets its fallback now, and
   * later calls get it at once, so a paywall button never stays locked.
   */
  fun detach() {
    val calls = synchronized(lock) {
      channel = null
      pending.toList().also { pending.clear() }
    }
    calls.forEach { it.finish(Reply.Unavailable("The Flutter engine was detached", PROVIDER_CODE_DETACHED)) }
  }

  /**
   * The first registration from a new Dart isolate (a hot restart): the calls
   * still waiting went to an isolate that no longer exists, so their reply
   * will never come. A no-op in production, where nothing is pending then.
   */
  fun retirePendingCalls() {
    val calls = synchronized(lock) { pending.toList().also { pending.clear() } }
    calls.forEach {
      it.finish(Reply.Unavailable("The Dart isolate that received this call was restarted", PROVIDER_CODE_UNAVAILABLE))
    }
  }

  // MARK: - Transport

  private inner class PendingCall(private val onReply: (Reply) -> Unit) {
    private val finished = AtomicBoolean(false)

    val timeout = Runnable { finish(Reply.TimedOut) }

    /** The first reply wins; later ones are dropped. */
    fun finish(reply: Reply) {
      if (!finished.compareAndSet(false, true)) return
      mainHandler.removeCallbacks(timeout)
      synchronized(lock) { pending.remove(this) }
      onReply(reply)
    }
  }

  private suspend fun call(method: String, arguments: Any?, timeoutMs: Long?): Reply =
    suspendCoroutine { continuation ->
      start(method, arguments, timeoutMs) { reply -> continuation.resume(reply) }
    }

  private fun start(method: String, arguments: Any?, timeoutMs: Long?, onReply: (Reply) -> Unit) {
    val call = PendingCall(onReply)
    runOnMain {
      val channel = synchronized(lock) { channel?.also { pending.add(call) } }
      if (channel == null) {
        call.finish(Reply.Unavailable("The Flutter engine was detached", PROVIDER_CODE_DETACHED))
        return@runOnMain
      }
      if (timeoutMs != null) mainHandler.postDelayed(call.timeout, timeoutMs)
      try {
        channel.invokeMethod(method, arguments, object : MethodChannel.Result {
          override fun success(result: Any?) = call.finish(Reply.Success(result))

          override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
            call.finish(Reply.Failure(errorCode, errorMessage, errorDetails))

          override fun notImplemented() = call.finish(
            Reply.Unavailable(
              "No Dart SetgreetPurchaseProvider is registered (Setgreet.setPurchaseProvider in Dart)",
              PROVIDER_CODE_UNAVAILABLE
            )
          )
        })
      } catch (e: Exception) {
        call.finish(Reply.Unavailable("The Dart purchase provider is unavailable: ${e.message}", PROVIDER_CODE_UNAVAILABLE))
      }
    }
  }

  private fun runOnMain(block: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
  }

  companion object {
    /** Longer than the SDK's own 10 s, which normally decides first. */
    const val SAFETY_TIMEOUT_MS = 30_000L

    private const val PROVIDER_CODE_UNAVAILABLE = "flutter_provider_unavailable"
    private const val PROVIDER_CODE_DETACHED = "flutter_engine_detached"

    // MARK: - Codec

    fun encodeSource(source: SetgreetPurchaseSource): Map<String, Any?> =
      mapOf("sourceType" to source.sourceType, "sourceId" to source.sourceId)

    /** A source from the channel; null when absent or malformed. */
    fun decodeSource(value: Any?): SetgreetPurchaseSource? {
      val map = value as? Map<*, *> ?: return null
      val sourceType = map["sourceType"] as? String ?: return null
      return SetgreetPurchaseSource(sourceType, map["sourceId"] as? String)
    }

    fun encodeImpression(context: SetgreetPaywallImpressionContext): Map<String, Any?> = mapOf(
      "flowId" to context.flowId,
      "screenId" to context.screenId,
      "source" to encodeSource(context.source),
      "productRefs" to context.productRefs
    )

    private fun purchaseError(reply: Reply.Failure): SetgreetPurchaseError = SetgreetPurchaseError(
      code = errorCode(reply.code),
      providerCode = (reply.details as? Map<*, *>)?.get("providerCode") as? String,
      message = reply.message
    )

    /**
     * An error reply to `purchase` or `restorePurchases`, which the Dart bridge
     * answers with a result even when the provider throws: something failed
     * outside the provider, so there is no usable provider.
     */
    private fun notConfigured(reply: Reply.Failure): SetgreetPurchaseError = SetgreetPurchaseError(
      code = SetgreetPurchaseErrorCode.NOT_CONFIGURED,
      providerCode = PROVIDER_CODE_UNAVAILABLE,
      message = "The Dart purchase bridge failed: ${reply.code} ${reply.message.orEmpty()}"
    )

    private fun errorCode(raw: Any?): SetgreetPurchaseErrorCode =
      SetgreetPurchaseErrorCode.values().firstOrNull { it.rawValue == raw } ?: SetgreetPurchaseErrorCode.UNKNOWN

    private fun decodeError(value: Any?): SetgreetPurchaseError? {
      val map = value as? Map<*, *> ?: return null
      return SetgreetPurchaseError(
        code = errorCode(map["code"]),
        providerCode = map["providerCode"] as? String,
        message = map["message"] as? String
      )
    }

    private fun stringList(value: Any?): List<String> =
      (value as? List<*>)?.filterIsInstance<String>() ?: emptyList()

    /** Products the Dart side could not describe completely are dropped. */
    private fun decodeProducts(value: Any?): List<SetgreetPurchaseProduct> =
      (value as? List<*>)?.mapNotNull { decodeProduct(it) } ?: emptyList()

    private fun decodeProduct(value: Any?): SetgreetPurchaseProduct? {
      val map = value as? Map<*, *> ?: return null
      return SetgreetPurchaseProduct(
        ref = map["ref"] as? String ?: return null,
        storeProductId = map["storeProductId"] as? String ?: return null,
        title = map["title"] as? String,
        description = map["description"] as? String,
        localizedPrice = map["localizedPrice"] as? String ?: return null,
        priceAmount = decimal(map["priceAmount"]) ?: return null,
        currencyCode = map["currencyCode"] as? String ?: return null,
        period = decodePeriod(map["period"]),
        introOffer = decodeIntroOffer(map["introOffer"])
      )
    }

    /**
     * `priceAmount` crosses the channel as a double. `BigDecimal.valueOf`
     * goes through the double's shortest decimal string, so 49.99 stays
     * 49.99 (`BigDecimal(double)` would keep the binary value's 50 digits).
     */
    internal fun decimal(value: Any?): BigDecimal? = when (value) {
      is Double -> if (value.isFinite()) BigDecimal.valueOf(value) else null
      is Float -> if (value.isFinite()) BigDecimal.valueOf(value.toDouble()) else null
      is Int -> BigDecimal.valueOf(value.toLong())
      is Long -> BigDecimal.valueOf(value)
      is String -> value.toBigDecimalOrNull()
      else -> null
    }

    private fun decodePeriod(value: Any?): SetgreetPurchasePeriod? {
      val map = value as? Map<*, *> ?: return null
      val unit = SetgreetPurchasePeriodUnit.values().firstOrNull { it.rawValue == map["unit"] } ?: return null
      val count = (map["count"] as? Number)?.toInt() ?: return null
      return SetgreetPurchasePeriod(unit, count)
    }

    private fun decodeIntroOffer(value: Any?): SetgreetPurchaseIntroOffer? {
      val map = value as? Map<*, *> ?: return null
      return SetgreetPurchaseIntroOffer(
        type = map["type"] as? String ?: return null,
        localizedPrice = map["localizedPrice"] as? String,
        periodText = map["periodText"] as? String,
        eligible = map["eligible"] as? Boolean
      )
    }

    /** An unknown status is `FAILED` with `UNKNOWN`. */
    private fun decodePurchaseResult(value: Any?, requestedRef: String): SetgreetPurchaseResult {
      val map = value as? Map<*, *>
      val productRef = (map?.get("productRef") as? String)?.takeIf { it.isNotEmpty() } ?: requestedRef
      val status = SetgreetPurchaseStatus.values().firstOrNull { it.rawValue == map?.get("status") }
        ?: return SetgreetPurchaseResult(
          SetgreetPurchaseStatus.FAILED,
          productRef,
          error = SetgreetPurchaseError(
            SetgreetPurchaseErrorCode.UNKNOWN,
            message = "The Dart purchase provider returned no known status (${map?.get("status")})"
          )
        )
      return SetgreetPurchaseResult(status, productRef, stringList(map?.get("accessRefs")), decodeError(map?.get("error")))
    }

    /** An unknown status is `FAILED` with `UNKNOWN`. */
    private fun decodeRestoreResult(value: Any?): SetgreetRestoreResult {
      val map = value as? Map<*, *>
      val status = SetgreetRestoreStatus.values().firstOrNull { it.rawValue == map?.get("status") }
        ?: return SetgreetRestoreResult(
          SetgreetRestoreStatus.FAILED,
          error = SetgreetPurchaseError(
            SetgreetPurchaseErrorCode.UNKNOWN,
            message = "The Dart purchase provider returned no known restore status (${map?.get("status")})"
          )
        )
      return SetgreetRestoreResult(status, stringList(map?.get("accessRefs")), decodeError(map?.get("error")))
    }

    /** null ("cannot say") unless the Dart side reported `active`. */
    private fun decodeAccessState(value: Any?): SetgreetPurchaseAccessState? {
      val map = value as? Map<*, *> ?: return null
      val active = map["active"] as? Boolean ?: return null
      return SetgreetPurchaseAccessState(active, stringList(map["accessRefs"]))
    }
  }
}

/**
 * The native purchase provider registered for a Dart one: every method is
 * answered by the Dart provider through [bridge]. The `Activity` the SDK
 * passes to [purchase] stays on the native side; a Dart provider buys
 * through its own plugin, which finds the Activity itself.
 */
internal class FlutterPurchaseProvider(
  override val providerId: String,
  private val bridge: FlutterPurchaseBridge
) : SetgreetPurchaseProvider {

  override suspend fun loadProducts(source: SetgreetPurchaseSource): List<SetgreetPurchaseProduct> =
    bridge.loadProducts(source)

  override suspend fun purchase(
    activity: Activity,
    productRef: String,
    source: SetgreetPurchaseSource
  ): SetgreetPurchaseResult = bridge.purchase(productRef, source)

  override suspend fun restorePurchases(): SetgreetRestoreResult = bridge.restorePurchases()

  override suspend fun accessState(): SetgreetPurchaseAccessState? = bridge.accessState()

  override fun trackPaywallImpression(context: SetgreetPaywallImpressionContext) {
    bridge.send("trackPaywallImpression", FlutterPurchaseBridge.encodeImpression(context))
  }

  override fun setAttributes(attributes: Map<String, String>) {
    bridge.send("setAttributes", mapOf("attributes" to attributes))
  }

  override suspend fun identify(userId: String) = bridge.identify(userId)

  override suspend fun reset() = bridge.reset()
}
