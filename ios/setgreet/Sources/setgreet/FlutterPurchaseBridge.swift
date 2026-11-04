import Flutter
import Foundation
import SetgreetSDK

/// The native end of the purchase bridge, one per Flutter engine.
///
/// The SDK calls a native `SetgreetPurchaseProvider`; in a Flutter app the
/// host's provider is a Dart object. `FlutterPurchaseProvider` is the native
/// provider registered with `Setgreet.shared.setPurchaseProvider`: each of
/// its methods invokes `setgreet/purchases` on the main thread, and the Dart
/// handler answers from the registered Dart provider (protocol:
/// `lib/src/purchase_bridge.dart`).
///
/// Every call resumes exactly once. Without a usable Dart provider (no
/// handler or "not implemented", the engine detached, or an old isolate after
/// a hot restart), `purchase` and `restorePurchases` report `failed` with
/// `notConfigured`, `loadProducts` throws `notConfigured`, `accessState` is
/// nil, and `identify` / `reset` return. An error reply depends on the
/// method: for `loadProducts` it is the Dart provider's own error and keeps
/// its code (a generic Flutter error, with no contract code, becomes
/// `unknown`); the Dart side answers `purchase` and `restorePurchases` with a
/// result even when the provider throws, so an error reply there means the
/// bridge itself failed and reports `notConfigured`; `accessState` is nil.
///
/// Timeouts: `loadProducts` and `accessState` give up after `safetyTimeout`,
/// longer than the SDK's own 10 s, so a Dart provider that never answers
/// cannot hold a call forever (`loadProducts` then throws `networkError` with
/// `providerCode` "timeout", as the SDK's own timeout does). `purchase` and
/// `restorePurchases` have none: a store sheet can stay open for minutes.
/// Neither have `identify` and `reset`: the SDK runs them one after another
/// and writes the access attributes once they are done, so cutting a slow
/// `logIn` short could write the previous user's access onto the new one.
/// The engine teardown still resolves all of them.
final class FlutterPurchaseBridge {

  /// Longer than the SDK's own 10 s, which normally decides first.
  static let defaultSafetyTimeout: TimeInterval = 30

  static let providerCodeUnavailable = "flutter_provider_unavailable"
  static let providerCodeDetached = "flutter_engine_detached"

  fileprivate enum Reply {
    case success(Any?)
    case failure(FlutterError)
    case unavailable(reason: String, providerCode: String)
    case timedOut
  }

  private let lock = NSLock()
  /// nil once the engine is detached. Guarded by `lock`.
  private var channel: FlutterMethodChannel?
  /// Calls waiting for a Dart reply. Guarded by `lock`.
  private var pending: [ObjectIdentifier: PendingCall] = [:]
  private let safetyTimeout: TimeInterval

  /// `safetyTimeout` is injectable for tests only.
  init(channel: FlutterMethodChannel, safetyTimeout: TimeInterval = FlutterPurchaseBridge.defaultSafetyTimeout) {
    self.channel = channel
    self.safetyTimeout = safetyTimeout
  }

  // MARK: - Provider calls

  func loadProducts(_ source: SetgreetPurchaseSource) async throws -> [SetgreetPurchaseProduct] {
    switch await call("loadProducts", arguments: ["source": Self.encode(source)], timeout: safetyTimeout) {
    case .success(let value):
      return Self.decodeProducts(value)
    case .failure(let error):
      // The Dart provider threw: its error, as the bridge encoded it.
      throw Self.purchaseError(error)
    case .unavailable(let reason, let providerCode):
      throw SetgreetPurchaseError(code: .notConfigured, providerCode: providerCode, message: reason)
    case .timedOut:
      throw SetgreetPurchaseError(
        code: .networkError,
        providerCode: "timeout",
        message: "loadProducts did not return within \(Int(safetyTimeout))s"
      )
    }
  }

  func purchase(productRef: String, source: SetgreetPurchaseSource) async -> SetgreetPurchaseResult {
    let arguments: [String: Any] = ["productRef": productRef, "source": Self.encode(source)]
    switch await call("purchase", arguments: arguments, timeout: nil) {
    case .success(let value):
      return Self.decodePurchaseResult(value, requestedRef: productRef)
    case .failure(let error):
      return SetgreetPurchaseResult(status: .failed, productRef: productRef, error: Self.notConfigured(error))
    case .unavailable(let reason, let providerCode):
      return SetgreetPurchaseResult(
        status: .failed,
        productRef: productRef,
        error: SetgreetPurchaseError(code: .notConfigured, providerCode: providerCode, message: reason)
      )
    case .timedOut:
      // No timeout is set for a purchase.
      return SetgreetPurchaseResult(status: .failed, productRef: productRef, error: SetgreetPurchaseError(code: .unknown))
    }
  }

  func restorePurchases() async -> SetgreetRestoreResult {
    switch await call("restorePurchases", arguments: nil, timeout: nil) {
    case .success(let value):
      return Self.decodeRestoreResult(value)
    case .failure(let error):
      return SetgreetRestoreResult(status: .failed, error: Self.notConfigured(error))
    case .unavailable(let reason, let providerCode):
      return SetgreetRestoreResult(
        status: .failed,
        error: SetgreetPurchaseError(code: .notConfigured, providerCode: providerCode, message: reason)
      )
    case .timedOut:
      // No timeout is set for a restore.
      return SetgreetRestoreResult(status: .failed, error: SetgreetPurchaseError(code: .unknown))
    }
  }

  func accessState() async -> SetgreetPurchaseAccessState? {
    if case .success(let value) = await call("accessState", arguments: nil, timeout: safetyTimeout) {
      return Self.decodeAccessState(value)
    }
    return nil
  }

  func identify(userId: String) async {
    _ = await call("identify", arguments: ["userId": userId], timeout: nil)
  }

  func reset() async {
    _ = await call("reset", arguments: nil, timeout: nil)
  }

  /// Fire-and-forget: the SDK does not wait for these.
  func send(_ method: String, arguments: Any?) {
    onMain {
      self.lock.lock()
      let channel = self.channel
      self.lock.unlock()
      channel?.invokeMethod(method, arguments: arguments)
    }
  }

  // MARK: - Lifecycle

  /// The engine is detached: every waiting call gets its fallback now, and
  /// later calls get it at once, so a paywall button never stays locked.
  func detach() {
    lock.lock()
    channel = nil
    let calls = Array(pending.values)
    pending.removeAll()
    lock.unlock()
    calls.forEach {
      $0.finish(.unavailable(reason: "The Flutter engine was detached", providerCode: Self.providerCodeDetached))
    }
  }

  /// The first registration from a new Dart isolate (a hot restart): the
  /// calls still waiting went to an isolate that no longer exists, so their
  /// reply will never come. A no-op in production, where nothing is pending
  /// then.
  func retirePendingCalls() {
    lock.lock()
    let calls = Array(pending.values)
    pending.removeAll()
    lock.unlock()
    calls.forEach {
      $0.finish(.unavailable(
        reason: "The Dart isolate that received this call was restarted",
        providerCode: Self.providerCodeUnavailable
      ))
    }
  }

  // MARK: - Transport

  private final class PendingCall {
    private let lock = NSLock()
    private var onReply: ((Reply) -> Void)?
    private var timeout: DispatchWorkItem?

    init(_ onReply: @escaping (Reply) -> Void) {
      self.onReply = onReply
    }

    func setTimeout(_ item: DispatchWorkItem) {
      lock.lock()
      timeout = item
      lock.unlock()
    }

    /// The first reply wins; later ones are dropped.
    func finish(_ reply: Reply) {
      lock.lock()
      let onReply = self.onReply
      self.onReply = nil
      let timeout = self.timeout
      self.timeout = nil
      lock.unlock()
      timeout?.cancel()
      onReply?(reply)
    }
  }

  private func call(_ method: String, arguments: Any?, timeout: TimeInterval?) async -> Reply {
    await withCheckedContinuation { (continuation: CheckedContinuation<Reply, Never>) in
      start(method, arguments: arguments, timeout: timeout) { reply in
        continuation.resume(returning: reply)
      }
    }
  }

  /// Invokes the Dart handler on the main thread, as the Flutter engine
  /// requires. The SDK calls provider methods from a background task.
  private func start(_ method: String, arguments: Any?, timeout: TimeInterval?, onReply: @escaping (Reply) -> Void) {
    let call = PendingCall(onReply)
    onMain {
      self.lock.lock()
      let channel = self.channel
      if channel != nil {
        self.pending[ObjectIdentifier(call)] = call
      }
      self.lock.unlock()

      guard let channel = channel else {
        call.finish(.unavailable(reason: "The Flutter engine was detached", providerCode: Self.providerCodeDetached))
        return
      }
      if let timeout = timeout {
        let item = DispatchWorkItem {
          self.complete(call, with: .timedOut)
        }
        call.setTimeout(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
      }
      channel.invokeMethod(method, arguments: arguments) { result in
        self.complete(call, with: Self.reply(from: result))
      }
    }
  }

  private func complete(_ call: PendingCall, with reply: Reply) {
    lock.lock()
    pending.removeValue(forKey: ObjectIdentifier(call))
    lock.unlock()
    call.finish(reply)
  }

  private static func reply(from result: Any?) -> Reply {
    if let error = result as? FlutterError {
      return .failure(error)
    }
    if let object = result as? NSObject, object === FlutterMethodNotImplemented {
      return .unavailable(
        reason: "No Dart SetgreetPurchaseProvider is registered (Setgreet.setPurchaseProvider in Dart)",
        providerCode: providerCodeUnavailable
      )
    }
    return .success(result)
  }

  private func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
    } else {
      DispatchQueue.main.async(execute: block)
    }
  }

  // MARK: - Codec

  static func encode(_ source: SetgreetPurchaseSource) -> [String: Any] {
    [
      "sourceType": source.sourceType,
      "sourceId": source.sourceId.map { $0 as Any } ?? NSNull(),
    ]
  }

  /// A source from the channel; nil when absent or malformed.
  static func decodeSource(_ value: Any?) -> SetgreetPurchaseSource? {
    guard let map = value as? [String: Any], let sourceType = map["sourceType"] as? String else {
      return nil
    }
    return SetgreetPurchaseSource(sourceType: sourceType, sourceId: map["sourceId"] as? String)
  }

  static func encode(_ context: SetgreetPaywallImpressionContext) -> [String: Any] {
    [
      "flowId": context.flowId,
      "screenId": context.screenId,
      "source": encode(context.source),
      "productRefs": context.productRefs,
    ]
  }

  private static func purchaseError(_ error: FlutterError) -> SetgreetPurchaseError {
    SetgreetPurchaseError(
      code: errorCode(error.code),
      providerCode: (error.details as? [String: Any])?["providerCode"] as? String,
      message: error.message
    )
  }

  /// An error reply to `purchase` or `restorePurchases`, which the Dart
  /// bridge answers with a result even when the provider throws: something
  /// failed outside the provider, so there is no usable provider.
  private static func notConfigured(_ error: FlutterError) -> SetgreetPurchaseError {
    SetgreetPurchaseError(
      code: .notConfigured,
      providerCode: providerCodeUnavailable,
      message: "The Dart purchase bridge failed: \(error.code) \(error.message ?? "")"
    )
  }

  private static func errorCode(_ raw: String?) -> SetgreetPurchaseErrorCode {
    raw.flatMap(SetgreetPurchaseErrorCode.init(rawValue:)) ?? .unknown
  }

  private static func decodeError(_ value: Any?) -> SetgreetPurchaseError? {
    guard let map = value as? [String: Any] else { return nil }
    return SetgreetPurchaseError(
      code: errorCode(map["code"] as? String),
      providerCode: map["providerCode"] as? String,
      message: map["message"] as? String
    )
  }

  private static func stringList(_ value: Any?) -> [String] {
    (value as? [Any])?.compactMap { $0 as? String } ?? []
  }

  /// Products the Dart side could not describe completely are dropped.
  private static func decodeProducts(_ value: Any?) -> [SetgreetPurchaseProduct] {
    (value as? [Any])?.compactMap(decodeProduct) ?? []
  }

  private static func decodeProduct(_ value: Any) -> SetgreetPurchaseProduct? {
    guard let map = value as? [String: Any],
          let ref = map["ref"] as? String,
          let storeProductId = map["storeProductId"] as? String,
          let localizedPrice = map["localizedPrice"] as? String,
          let priceAmount = decimal(map["priceAmount"]),
          let currencyCode = map["currencyCode"] as? String else {
      return nil
    }
    return SetgreetPurchaseProduct(
      ref: ref,
      storeProductId: storeProductId,
      title: map["title"] as? String,
      description: map["description"] as? String,
      localizedPrice: localizedPrice,
      priceAmount: priceAmount,
      currencyCode: currencyCode,
      period: decodePeriod(map["period"]),
      introOffer: decodeIntroOffer(map["introOffer"])
    )
  }

  /// `priceAmount` crosses the channel as a double. Its shortest decimal
  /// string ("49.99") becomes the `Decimal`, never its binary value
  /// (`Decimal(49.99)` is 49.99000000000000512).
  static func decimal(_ value: Any?) -> Decimal? {
    let posix = Locale(identifier: "en_US_POSIX")
    if let number = value as? NSNumber {
      let double = number.doubleValue
      guard double.isFinite else { return nil }
      return Decimal(string: "\(double)", locale: posix)
    }
    if let string = value as? String {
      return Decimal(string: string, locale: posix)
    }
    return nil
  }

  private static func decodePeriod(_ value: Any?) -> SetgreetPurchasePeriod? {
    guard let map = value as? [String: Any],
          let rawUnit = map["unit"] as? String,
          let unit = SetgreetPurchasePeriodUnit(rawValue: rawUnit),
          let count = map["count"] as? Int else {
      return nil
    }
    return SetgreetPurchasePeriod(unit: unit, count: count)
  }

  private static func decodeIntroOffer(_ value: Any?) -> SetgreetPurchaseIntroOffer? {
    guard let map = value as? [String: Any], let type = map["type"] as? String else { return nil }
    return SetgreetPurchaseIntroOffer(
      type: type,
      localizedPrice: map["localizedPrice"] as? String,
      periodText: map["periodText"] as? String,
      eligible: map["eligible"] as? Bool
    )
  }

  /// An unknown status is `failed` with `unknown`.
  private static func decodePurchaseResult(_ value: Any?, requestedRef: String) -> SetgreetPurchaseResult {
    let map = value as? [String: Any]
    let returnedRef = map?["productRef"] as? String
    let productRef = (returnedRef?.isEmpty == false ? returnedRef : nil) ?? requestedRef
    guard let rawStatus = map?["status"] as? String,
          let status = SetgreetPurchaseStatus(rawValue: rawStatus) else {
      return SetgreetPurchaseResult(
        status: .failed,
        productRef: productRef,
        error: SetgreetPurchaseError(
          code: .unknown,
          message: "The Dart purchase provider returned no known status (\(String(describing: map?["status"])))"
        )
      )
    }
    return SetgreetPurchaseResult(
      status: status,
      productRef: productRef,
      accessRefs: stringList(map?["accessRefs"]),
      error: decodeError(map?["error"])
    )
  }

  /// An unknown status is `failed` with `unknown`.
  private static func decodeRestoreResult(_ value: Any?) -> SetgreetRestoreResult {
    let map = value as? [String: Any]
    guard let rawStatus = map?["status"] as? String,
          let status = SetgreetRestoreStatus(rawValue: rawStatus) else {
      return SetgreetRestoreResult(
        status: .failed,
        error: SetgreetPurchaseError(
          code: .unknown,
          message: "The Dart purchase provider returned no known restore status (\(String(describing: map?["status"])))"
        )
      )
    }
    return SetgreetRestoreResult(
      status: status,
      accessRefs: stringList(map?["accessRefs"]),
      error: decodeError(map?["error"])
    )
  }

  /// nil ("cannot say") unless the Dart side reported `active`.
  private static func decodeAccessState(_ value: Any?) -> SetgreetPurchaseAccessState? {
    guard let map = value as? [String: Any], let active = map["active"] as? Bool else { return nil }
    return SetgreetPurchaseAccessState(active: active, accessRefs: stringList(map["accessRefs"]))
  }
}

/// The native purchase provider registered for a Dart one: every method is
/// answered by the Dart provider through the engine's bridge.
final class FlutterPurchaseProvider: SetgreetPurchaseProvider {

  let providerId: String
  private let bridge: FlutterPurchaseBridge

  init(providerId: String, bridge: FlutterPurchaseBridge) {
    self.providerId = providerId
    self.bridge = bridge
  }

  func loadProducts(_ source: SetgreetPurchaseSource) async throws -> [SetgreetPurchaseProduct] {
    try await bridge.loadProducts(source)
  }

  func purchase(productRef: String, source: SetgreetPurchaseSource) async -> SetgreetPurchaseResult {
    await bridge.purchase(productRef: productRef, source: source)
  }

  func restorePurchases() async -> SetgreetRestoreResult {
    await bridge.restorePurchases()
  }

  func accessState() async -> SetgreetPurchaseAccessState? {
    await bridge.accessState()
  }

  func trackPaywallImpression(_ context: SetgreetPaywallImpressionContext) {
    bridge.send("trackPaywallImpression", arguments: FlutterPurchaseBridge.encode(context))
  }

  func setAttributes(_ attributes: [String: String]) {
    bridge.send("setAttributes", arguments: ["attributes": attributes])
  }

  func identify(userId: String) async {
    await bridge.identify(userId: userId)
  }

  func reset() async {
    await bridge.reset()
  }
}
