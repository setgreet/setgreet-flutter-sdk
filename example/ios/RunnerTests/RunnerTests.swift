import Flutter
import SetgreetSDK
import UIKit
import XCTest

@testable import setgreet

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}

// MARK: - Purchase bridge (the plugin's native end of `setgreet/purchases`)

/// Records what the bridge sends on its channel and lets a test answer it,
/// as the Flutter engine would.
final class FakeBinaryMessenger: NSObject, FlutterBinaryMessenger {
  struct Message {
    let channel: String
    let call: FlutterMethodCall
    let reply: FlutterBinaryReply?
  }

  private(set) var messages: [Message] = []
  private let codec = FlutterStandardMethodCodec.sharedInstance()

  func send(onChannel channel: String, message: Data?) {
    record(channel, message, nil)
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    record(channel, message, callback)
  }

  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    0
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}

  /// The Dart side returned [value].
  func succeed(_ index: Int, _ value: Any?) {
    messages[index].reply?(codec.encodeSuccessEnvelope(value))
  }

  /// The Dart side answered with an error.
  func fail(_ index: Int, _ error: FlutterError) {
    messages[index].reply?(codec.encodeErrorEnvelope(error))
  }

  /// No Dart handler: the engine answers with an empty reply.
  func notImplemented(_ index: Int) {
    messages[index].reply?(nil)
  }

  private func record(_ channel: String, _ message: Data?, _ reply: FlutterBinaryReply?) {
    guard let message = message else { return }
    messages.append(Message(channel: channel, call: codec.decodeMethodCall(message), reply: reply))
  }
}

@MainActor
final class PurchaseBridgeTests: XCTestCase {

  private let source = SetgreetPurchaseSource.offering("discount")

  private func makeBridge(safetyTimeout: TimeInterval = 0.1) -> (FlutterPurchaseBridge, FakeBinaryMessenger) {
    let messenger = FakeBinaryMessenger()
    let channel = FlutterMethodChannel(name: "setgreet/purchases", binaryMessenger: messenger)
    return (FlutterPurchaseBridge(channel: channel, safetyTimeout: safetyTimeout), messenger)
  }

  /// Starts [operation] and waits (up to 5 s) until its call reached the
  /// messenger.
  private func start<T>(
    _ messenger: FakeBinaryMessenger,
    _ operation: @escaping @MainActor () async -> T
  ) async -> Task<T, Never> {
    let before = messenger.messages.count
    let task = Task { await operation() }
    let deadline = Date().addingTimeInterval(5)
    while messenger.messages.count == before && Date() < deadline {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertEqual(messenger.messages.count, before + 1, "the call never reached the channel")
    return task
  }

  private func arguments(_ messenger: FakeBinaryMessenger, _ index: Int) -> [String: Any]? {
    messenger.messages[index].call.arguments as? [String: Any]
  }

  private func loadProducts(_ bridge: FlutterPurchaseBridge) async -> Result<[SetgreetPurchaseProduct], Error> {
    do {
      return .success(try await bridge.loadProducts(source))
    } catch {
      return .failure(error)
    }
  }

  private func purchaseError(_ result: Result<[SetgreetPurchaseProduct], Error>) -> SetgreetPurchaseError? {
    if case .failure(let error) = result { return error as? SetgreetPurchaseError }
    return nil
  }

  // MARK: Exactly once

  func testAccessStateTimesOutAndIgnoresALateReply() async {
    let (bridge, messenger) = makeBridge(safetyTimeout: 0.05)
    let task = await start(messenger) { await bridge.accessState() }

    let state = await task.value
    XCTAssertNil(state, "a timeout is 'cannot say'")

    // The Dart side answers after the timeout: the call already resumed, and
    // a second resume would trap the test process.
    messenger.succeed(0, ["active": true, "accessRefs": ["premium"]])

    let next = await start(messenger) { await bridge.accessState() }
    messenger.succeed(1, ["active": true, "accessRefs": ["premium"]])
    let answered = await next.value
    XCTAssertEqual(answered?.active, true)
    XCTAssertEqual(answered?.accessRefs, ["premium"])
  }

  func testLoadProductsTimeoutMirrorsTheSDKsOwnTimeoutError() async {
    let (bridge, messenger) = makeBridge(safetyTimeout: 0.05)
    let task = await start(messenger) { await self.loadProducts(bridge) }

    let error = purchaseError(await task.value)
    XCTAssertEqual(error?.code, .networkError)
    XCTAssertEqual(error?.providerCode, "timeout")

    messenger.succeed(0, [])
  }

  func testPurchaseAndIdentifyHaveNoTimeout() async throws {
    let (bridge, messenger) = makeBridge(safetyTimeout: 0.05)
    var purchaseDone = false
    var identifyDone = false
    let purchase = await start(messenger) { () -> SetgreetPurchaseResult in
      let result = await bridge.purchase(productRef: "$rc_annual", source: self.source)
      purchaseDone = true
      return result
    }
    let identify = await start(messenger) { () -> Void in
      await bridge.identify(userId: "user-42")
      identifyDone = true
    }

    XCTAssertEqual(messenger.messages.map(\.call.method), ["purchase", "identify"])
    XCTAssertEqual(arguments(messenger, 0)?["productRef"] as? String, "$rc_annual")
    let purchaseSource = arguments(messenger, 0)?["source"] as? [String: Any]
    XCTAssertEqual(purchaseSource?["sourceType"] as? String, "offering")
    XCTAssertEqual(purchaseSource?["sourceId"] as? String, "discount")

    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertFalse(purchaseDone, "a store sheet can stay open for minutes")
    XCTAssertFalse(identifyDone, "the SDK waits for identify before writing attributes")

    messenger.succeed(0, ["status": "purchased", "productRef": "$rc_annual", "accessRefs": ["premium"], "error": NSNull()])
    messenger.succeed(1, nil)
    let result = await purchase.value
    await identify.value
    XCTAssertEqual(result.status, .purchased)
    XCTAssertEqual(result.accessRefs, ["premium"])
    XCTAssertEqual(messenger.messages[1].call.method, "identify")
    XCTAssertEqual((messenger.messages[1].call.arguments as? [String: Any])?["userId"] as? String, "user-42")
  }

  // MARK: Teardown

  func testDetachResolvesEveryPendingCall() async {
    let (bridge, messenger) = makeBridge(safetyTimeout: 60)
    let purchase = await start(messenger) { await bridge.purchase(productRef: "$rc_annual", source: self.source) }
    let restore = await start(messenger) { await bridge.restorePurchases() }
    let load = await start(messenger) { await self.loadProducts(bridge) }
    let access = await start(messenger) { await bridge.accessState() }
    let identify = await start(messenger) { await bridge.identify(userId: "user-42") }
    let reset = await start(messenger) { await bridge.reset() }
    XCTAssertEqual(
      messenger.messages.map(\.call.method),
      ["purchase", "restorePurchases", "loadProducts", "accessState", "identify", "reset"]
    )
    XCTAssertTrue(messenger.messages[1].call.arguments is NSNull || messenger.messages[1].call.arguments == nil)

    bridge.detach()

    let purchased = await purchase.value
    XCTAssertEqual(purchased.status, .failed)
    XCTAssertEqual(purchased.productRef, "$rc_annual")
    XCTAssertEqual(purchased.error?.code, .notConfigured)
    XCTAssertEqual(purchased.error?.providerCode, FlutterPurchaseBridge.providerCodeDetached)
    let restored = await restore.value
    XCTAssertEqual(restored.status, .failed)
    XCTAssertEqual(restored.error?.code, .notConfigured)
    let loaded = await load.value
    XCTAssertEqual(purchaseError(loaded)?.code, .notConfigured)
    let state = await access.value
    XCTAssertNil(state)
    await identify.value
    await reset.value

    // Late replies to the dead engine's calls are dropped.
    for index in 0..<messenger.messages.count {
      messenger.notImplemented(index)
    }

    // Later calls resolve at once and send nothing.
    let later = await bridge.purchase(productRef: "$rc_monthly", source: source)
    XCTAssertEqual(later.error?.code, .notConfigured)
    XCTAssertEqual(messenger.messages.count, 6)
  }

  func testAHotRestartRetiresTheCallsTheOldIsolateNeverAnswers() async {
    let (bridge, messenger) = makeBridge()
    let purchase = await start(messenger) { await bridge.purchase(productRef: "$rc_annual", source: self.source) }

    bridge.retirePendingCalls()

    let result = await purchase.value
    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(result.error?.code, .notConfigured)
    XCTAssertEqual(result.error?.providerCode, FlutterPurchaseBridge.providerCodeUnavailable)

    // The channel itself still works for the new isolate.
    let next = await start(messenger) { await bridge.restorePurchases() }
    messenger.succeed(1, ["status": "nothingToRestore", "accessRefs": [], "error": NSNull()])
    let restored = await next.value
    XCTAssertEqual(restored.status, .nothingToRestore)
  }

  // MARK: No usable Dart provider

  func testNotImplementedMeansNoProvider() async {
    let (bridge, messenger) = makeBridge()
    let purchase = await start(messenger) { await bridge.purchase(productRef: "$rc_annual", source: self.source) }
    let restore = await start(messenger) { await bridge.restorePurchases() }
    let load = await start(messenger) { await self.loadProducts(bridge) }
    let access = await start(messenger) { await bridge.accessState() }
    (0..<4).forEach(messenger.notImplemented)

    let purchased = await purchase.value
    XCTAssertEqual(purchased.status, .failed)
    XCTAssertEqual(purchased.error?.code, .notConfigured)
    XCTAssertEqual(purchased.error?.providerCode, FlutterPurchaseBridge.providerCodeUnavailable)
    let restored = await restore.value
    XCTAssertEqual(restored.error?.code, .notConfigured)
    let loaded = await load.value
    XCTAssertEqual(purchaseError(loaded)?.code, .notConfigured)
    let state = await access.value
    XCTAssertNil(state)
  }

  func testAnUnexpectedErrorReplyToAPurchaseIsNotConfigured() async {
    let (bridge, messenger) = makeBridge()
    let purchase = await start(messenger) { await bridge.purchase(productRef: "$rc_annual", source: self.source) }
    messenger.fail(0, FlutterError(code: "error", message: "boom", details: nil))

    let result = await purchase.value
    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(result.error?.code, .notConfigured)
  }

  func testALoadProductsErrorReplyKeepsTheProvidersError() async {
    let (bridge, messenger) = makeBridge()
    let load = await start(messenger) { await self.loadProducts(bridge) }
    messenger.fail(0, FlutterError(code: "network_error", message: "offline", details: ["providerCode": "NetworkError"]))

    let error = purchaseError(await load.value)
    XCTAssertEqual(error?.code, .networkError)
    XCTAssertEqual(error?.providerCode, "NetworkError")
    XCTAssertEqual(error?.message, "offline")
  }

  // MARK: Decoding

  func testDecodesProductsKeepingExactPrices() async throws {
    let (bridge, messenger) = makeBridge()
    let load = await start(messenger) { await self.loadProducts(bridge) }

    let call = messenger.messages[0].call
    XCTAssertEqual(call.method, "loadProducts")
    let sent = (call.arguments as? [String: Any])?["source"] as? [String: Any]
    XCTAssertEqual(sent?["sourceType"] as? String, "offering")
    XCTAssertEqual(sent?["sourceId"] as? String, "discount")

    messenger.succeed(0, [
      [
        "ref": "$rc_annual",
        "storeProductId": "com.app.premium.annual",
        "title": "Premium Annual",
        "description": "Full access",
        "localizedPrice": "$49.99",
        "priceAmount": 49.99,
        "currencyCode": "USD",
        "period": ["unit": "year", "count": 1],
        "introOffer": ["type": "trial", "localizedPrice": "$0.00", "periodText": "7 days", "eligible": true],
      ],
      [
        "ref": "lifetime",
        "storeProductId": "com.app.lifetime",
        "title": NSNull(),
        "description": NSNull(),
        "localizedPrice": "$99.00",
        "priceAmount": 99.0,
        "currencyCode": "USD",
        "period": NSNull(),
        "introOffer": NSNull(),
      ],
      [
        // No ref: dropped.
        "storeProductId": "com.app.broken",
        "localizedPrice": "$1.99",
        "priceAmount": 1.99,
        "currencyCode": "USD",
      ],
    ])

    let products = try await load.value.get()
    XCTAssertEqual(products.map(\.ref), ["$rc_annual", "lifetime"])

    let annual = products[0]
    XCTAssertEqual(annual.priceAmount, Decimal(string: "49.99"))
    XCTAssertEqual(NSDecimalNumber(decimal: annual.priceAmount).stringValue, "49.99")
    XCTAssertEqual(annual.storeProductId, "com.app.premium.annual")
    XCTAssertEqual(annual.title, "Premium Annual")
    XCTAssertEqual(annual.description, "Full access")
    XCTAssertEqual(annual.localizedPrice, "$49.99")
    XCTAssertEqual(annual.currencyCode, "USD")
    XCTAssertEqual(annual.period, SetgreetPurchasePeriod(unit: .year, count: 1))
    XCTAssertEqual(annual.introOffer, SetgreetPurchaseIntroOffer(type: "trial", localizedPrice: "$0.00", periodText: "7 days", eligible: true))

    let lifetime = products[1]
    XCTAssertEqual(lifetime.priceAmount, Decimal(99))
    XCTAssertNil(lifetime.title)
    XCTAssertNil(lifetime.description)
    XCTAssertNil(lifetime.period)
    XCTAssertNil(lifetime.introOffer)
  }

  func testUnknownStatusesAreFailedAndMissingFieldsAreCoerced() async {
    let (bridge, messenger) = makeBridge()
    let purchase = await start(messenger) { await bridge.purchase(productRef: "$rc_annual", source: self.source) }
    let restore = await start(messenger) { await bridge.restorePurchases() }
    let access = await start(messenger) { await bridge.accessState() }
    let pending = await start(messenger) { await bridge.purchase(productRef: "$rc_monthly", source: self.source) }

    messenger.succeed(0, ["status": "bogus", "productRef": "$rc_annual"])
    messenger.succeed(1, ["status": "partial"])
    messenger.succeed(2, ["accessRefs": ["premium"]])
    messenger.succeed(3, ["status": "pending", "error": ["code": "purchase_pending", "providerCode": "paymentPendingError", "message": NSNull()]])

    let purchased = await purchase.value
    XCTAssertEqual(purchased.status, .failed)
    XCTAssertEqual(purchased.error?.code, .unknown)
    let restored = await restore.value
    XCTAssertEqual(restored.status, .failed)
    XCTAssertEqual(restored.error?.code, .unknown)
    XCTAssertEqual(restored.accessRefs, [])
    let state = await access.value
    XCTAssertNil(state, "no `active`: cannot say")
    let deferred = await pending.value
    XCTAssertEqual(deferred.status, .pending)
    XCTAssertEqual(deferred.productRef, "$rc_monthly", "a missing productRef is the requested one")
    XCTAssertEqual(deferred.accessRefs, [])
    XCTAssertEqual(deferred.error?.code, .purchasePending)
    XCTAssertEqual(deferred.error?.providerCode, "paymentPendingError")
  }

  // MARK: Fire-and-forget

  func testImpressionsAndAttributesAreSentWithoutWaiting() {
    let (bridge, messenger) = makeBridge()
    let provider = FlutterPurchaseProvider(providerId: "revenuecat", bridge: bridge)
    XCTAssertEqual(provider.providerId, "revenuecat")

    provider.trackPaywallImpression(SetgreetPaywallImpressionContext(
      flowId: "flow-1", screenId: "screen-1", source: source, productRefs: ["$rc_annual"]
    ))
    provider.setAttributes(["setgreet_flow": "flow-1"])

    XCTAssertEqual(messenger.messages.map(\.call.method), ["trackPaywallImpression", "setAttributes"])
    let impression = messenger.messages[0].call.arguments as? [String: Any]
    XCTAssertEqual(impression?["flowId"] as? String, "flow-1")
    XCTAssertEqual(impression?["screenId"] as? String, "screen-1")
    XCTAssertEqual(impression?["productRefs"] as? [String], ["$rc_annual"])
    XCTAssertEqual((impression?["source"] as? [String: Any])?["sourceId"] as? String, "discount")
    let attributes = messenger.messages[1].call.arguments as? [String: Any]
    XCTAssertEqual(attributes?["attributes"] as? [String: String], ["setgreet_flow": "flow-1"])
  }

  // MARK: Event maps

  func testPurchaseEventMapsCarryTheContractKeys() {
    let plugin = SetgreetPlugin(
      purchaseChannel: FlutterMethodChannel(name: "setgreet/purchases", binaryMessenger: FakeBinaryMessenger())
    )
    let common: Set<String> = ["type", "flowId", "screenId", "componentId", "provider", "timestamp"]
    let error = SetgreetPurchaseError(code: .networkError, providerCode: nil, message: "offline")

    let maps: [(String, [String: Any], Set<String>)] = [
      ("purchaseCompleted", plugin.createPurchaseCompletedEvent(PurchaseCompletedEvent(
        flowId: "flow-1", screenId: "screen-1", componentId: "buy", productRef: "$rc_annual",
        provider: "revenuecat", accessRefs: ["premium"], timestamp: 1_760_000_000
      )), ["productRef", "accessRefs"]),
      ("purchaseCancelled", plugin.createPurchaseCancelledEvent(PurchaseCancelledEvent(
        flowId: "flow-1", screenId: "screen-1", componentId: "buy", productRef: "$rc_annual",
        provider: "revenuecat", timestamp: 1_760_000_000
      )), ["productRef"]),
      ("purchaseFailed", plugin.createPurchaseFailedEvent(PurchaseFailedEvent(
        flowId: "flow-1", screenId: "screen-1", componentId: "buy", productRef: "$rc_annual",
        provider: "revenuecat", error: error, timestamp: 1_760_000_000
      )), ["productRef", "error"]),
      ("purchasePending", plugin.createPurchasePendingEvent(PurchasePendingEvent(
        flowId: "flow-1", screenId: "screen-1", componentId: "buy", productRef: "$rc_annual",
        provider: "revenuecat", timestamp: 1_760_000_000
      )), ["productRef"]),
      ("restoreCompleted", plugin.createRestoreCompletedEvent(RestoreCompletedEvent(
        flowId: "flow-1", screenId: "screen-1", componentId: "restore", provider: "revenuecat",
        status: .nothingToRestore, accessRefs: [], timestamp: 1_760_000_000
      )), ["status", "accessRefs"]),
      ("restoreFailed", plugin.createRestoreFailedEvent(RestoreFailedEvent(
        flowId: "flow-1", screenId: "screen-1", componentId: "restore", provider: "revenuecat",
        error: error, timestamp: 1_760_000_000
      )), ["error"]),
    ]

    for (type, map, extra) in maps {
      XCTAssertEqual(Set(map.keys), common.union(extra), type)
      XCTAssertEqual(map["type"] as? String, type)
      XCTAssertEqual(map["flowId"] as? String, "flow-1", type)
      XCTAssertEqual(map["provider"] as? String, "revenuecat", type)
      XCTAssertEqual(map["timestamp"] as? Double, 1_760_000_000_000, "\(type): milliseconds, as on Android")
    }

    XCTAssertEqual(maps[0].1["accessRefs"] as? [String], ["premium"])
    XCTAssertEqual(maps[4].1["status"] as? String, "nothingToRestore")
    let failed = maps[2].1["error"] as? [String: Any]
    XCTAssertEqual(failed?["code"] as? String, "network_error")
    XCTAssertTrue(failed?["providerCode"] is NSNull)
    XCTAssertEqual(failed?["message"] as? String, "offline")
  }
}
