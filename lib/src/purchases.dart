// The host-implemented purchase interface behind native paywalls.
//
// Setgreet wraps no vendor SDK and keeps no entitlement state: the host app
// implements [SetgreetPurchaseProvider] in its own Dart code on top of
// whatever it already uses (RevenueCat, Adapty, StoreKit, Play Billing, ...)
// and registers one instance with `Setgreet.setPurchaseProvider`. The native
// SDK then owns the loading state, the plan picker, live price tokens, the
// purchase lock, branching on the result, analytics and the catalog sync,
// and reaches this provider over the plugin's internal bridge.
//
// The names mirror the iOS and Android SDKs. Two methods differ: Dart's
// trackPaywallImpression and setAttributes have no-op defaults, while the
// native interfaces require them. Wire contract:
// setgreet-backend/docs/PAYWALL_PROVIDERS.md §2.11.

import 'package:flutter/foundation.dart';

/// Where a paywall's products come from, in the provider's own vocabulary.
@immutable
class SetgreetPurchaseSource {
  /// A source by its raw [sourceType] (`"current_offering"`, `"offering"` or
  /// `"placement"`) and [sourceId]. Prefer the named constructors.
  const SetgreetPurchaseSource({required this.sourceType, this.sourceId});

  /// The provider's current offering (the default source).
  const SetgreetPurchaseSource.currentOffering()
      : sourceType = 'current_offering',
        sourceId = null;

  /// A specific offering by identifier.
  const SetgreetPurchaseSource.offering(String identifier)
      : sourceType = 'offering',
        sourceId = identifier;

  /// The offering a placement resolves to.
  const SetgreetPurchaseSource.placement(String identifier)
      : sourceType = 'placement',
        sourceId = identifier;

  /// `"current_offering"` (the default), `"offering"` or `"placement"`.
  final String sourceType;

  /// The offering or placement identifier. Required for `"offering"` and
  /// `"placement"`, null for the current offering.
  final String? sourceId;

  @override
  bool operator ==(Object other) =>
      other is SetgreetPurchaseSource &&
      other.sourceType == sourceType &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(sourceType, sourceId);

  @override
  String toString() =>
      'SetgreetPurchaseSource(sourceType: $sourceType, sourceId: $sourceId)';
}

/// Units a subscription period is expressed in. [rawValue] is the wire value.
enum SetgreetPurchasePeriodUnit {
  day('day'),
  week('week'),
  month('month'),
  year('year');

  const SetgreetPurchasePeriodUnit(this.rawValue);

  /// The wire value.
  final String rawValue;
}

/// How often a subscription renews. A product without a period is a one-time
/// (lifetime) purchase.
@immutable
class SetgreetPurchasePeriod {
  const SetgreetPurchasePeriod({required this.unit, required this.count});

  final SetgreetPurchasePeriodUnit unit;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is SetgreetPurchasePeriod &&
      other.unit == unit &&
      other.count == count;

  @override
  int get hashCode => Object.hash(unit, count);

  @override
  String toString() => 'SetgreetPurchasePeriod(${unit.rawValue} x $count)';
}

/// An introductory offer attached to a product.
@immutable
class SetgreetPurchaseIntroOffer {
  const SetgreetPurchaseIntroOffer({
    required this.type,
    this.localizedPrice,
    this.periodText,
    this.eligible,
  });

  /// The [type] of a free trial.
  static const String trialType = 'trial';

  /// `"trial"` for a free trial. The SDK derives `trialText` from trials
  /// only; other values (`"payAsYouGo"`, `"payUpFront"`) pass through to the
  /// catalog sync untouched.
  final String type;

  /// The offer's localized price, when it has one.
  final String? localizedPrice;

  /// The offer's length as the provider formats it, e.g. `"7 days"`.
  final String? periodText;

  /// Whether this user is eligible; null when the provider cannot say. The
  /// SDK derives `trialText` only when this is `true`.
  final bool? eligible;

  @override
  String toString() =>
      'SetgreetPurchaseIntroOffer(type: $type, eligible: $eligible)';
}

/// One purchasable product, normalized from the provider's own model.
@immutable
class SetgreetPurchaseProduct {
  const SetgreetPurchaseProduct({
    required this.ref,
    required this.storeProductId,
    this.title,
    this.description,
    required this.localizedPrice,
    required this.priceAmount,
    required this.currencyCode,
    this.period,
    this.introOffer,
  }) : assert(
          // `priceAmount.isFinite`, written as a constant expression (NaN
          // fails both comparisons) so the constructor stays const.
          priceAmount > double.negativeInfinity &&
              priceAmount < double.infinity,
          'priceAmount must be a finite number',
        );

  /// The provider-side stable reference a flow refers to: a RevenueCat
  /// package identifier (`$rc_annual`), an Adapty `vendorProductId`, a store
  /// product id. This is what `productRef` and `{{purchase.<ref>.*}}` name.
  /// Unique within its source only: `$rc_annual` exists in every RevenueCat
  /// offering, so a ref names a product together with its source.
  final String ref;

  /// The store's product identifier.
  final String storeProductId;

  final String? title;
  final String? description;

  /// The price as the store formats it for this user, e.g. `"$49.99"`.
  final String localizedPrice;

  /// The price as a number in [currencyCode], e.g. `49.99`.
  ///
  /// A `double`, the type purchases_flutter reports prices in. The native
  /// SDKs keep prices as exact decimals: the plugin converts this value
  /// through its shortest decimal form (`49.99` stays `49.99`), never through
  /// its binary value.
  final double priceAmount;

  /// ISO 4217 code, e.g. `"USD"`.
  final String currencyCode;

  /// null for a one-time purchase.
  final SetgreetPurchasePeriod? period;

  final SetgreetPurchaseIntroOffer? introOffer;

  @override
  String toString() =>
      'SetgreetPurchaseProduct(ref: $ref, storeProductId: $storeProductId, '
      'localizedPrice: $localizedPrice)';
}

/// The outcome of [SetgreetPurchaseProvider.purchase]. [rawValue] is the
/// Response Split value the SDK sets on the button.
enum SetgreetPurchaseStatus {
  purchased('purchased'),
  cancelled('cancelled'),
  failed('failed'),
  pending('pending');

  const SetgreetPurchaseStatus(this.rawValue);

  /// The wire value.
  final String rawValue;
}

@immutable
class SetgreetPurchaseResult {
  const SetgreetPurchaseResult({
    required this.status,
    required this.productRef,
    this.accessRefs = const <String>[],
    this.error,
  });

  final SetgreetPurchaseStatus status;
  final String productRef;

  /// The access (entitlement) refs the user now holds.
  final List<String> accessRefs;

  final SetgreetPurchaseError? error;

  @override
  String toString() =>
      'SetgreetPurchaseResult(status: ${status.rawValue}, productRef: $productRef, '
      'accessRefs: $accessRefs, error: $error)';
}

/// The outcome of [SetgreetPurchaseProvider.restorePurchases]. [rawValue] is
/// the Response Split value the SDK sets on the button.
enum SetgreetRestoreStatus {
  restored('restored'),
  nothingToRestore('nothingToRestore'),
  failed('failed');

  const SetgreetRestoreStatus(this.rawValue);

  /// The wire value.
  final String rawValue;
}

@immutable
class SetgreetRestoreResult {
  const SetgreetRestoreResult({
    required this.status,
    this.accessRefs = const <String>[],
    this.error,
  });

  final SetgreetRestoreStatus status;

  /// The access (entitlement) refs the user now holds.
  final List<String> accessRefs;

  final SetgreetPurchaseError? error;

  @override
  String toString() =>
      'SetgreetRestoreResult(status: ${status.rawValue}, accessRefs: $accessRefs, '
      'error: $error)';
}

/// What the user currently has access to, as the provider reports it.
@immutable
class SetgreetPurchaseAccessState {
  const SetgreetPurchaseAccessState({
    required this.active,
    required this.accessRefs,
  });

  final bool active;
  final List<String> accessRefs;

  @override
  String toString() =>
      'SetgreetPurchaseAccessState(active: $active, accessRefs: $accessRefs)';
}

/// Normalized error codes. [rawValue] is what analytics carry as `errorCode`.
enum SetgreetPurchaseErrorCode {
  notConfigured('not_configured'),
  providerNotInitialized('provider_not_initialized'),
  productNotFound('product_not_found'),
  productUnavailable('product_unavailable'),
  purchaseCancelled('purchase_cancelled'),
  purchaseFailed('purchase_failed'),
  purchasePending('purchase_pending'),
  restoreFailed('restore_failed'),
  networkError('network_error'),
  identityError('identity_error'),
  unknown('unknown');

  const SetgreetPurchaseErrorCode(this.rawValue);

  /// The wire value, e.g. `"network_error"`.
  final String rawValue;

  /// The code whose [rawValue] is [value]; [unknown] for anything else.
  static SetgreetPurchaseErrorCode fromRawValue(String? value) {
    for (final code in values) {
      if (code.rawValue == value) return code;
    }
    return unknown;
  }
}

/// A normalized purchase error. Throw it from
/// [SetgreetPurchaseProvider.loadProducts]; return it in a result everywhere
/// else.
@immutable
class SetgreetPurchaseError implements Exception {
  const SetgreetPurchaseError({
    required this.code,
    this.providerCode,
    this.message,
  });

  final SetgreetPurchaseErrorCode code;

  /// The vendor's own code, for the host's logs and analytics.
  final String? providerCode;

  /// The vendor's message. Shown to end users only in `debugMode`.
  final String? message;

  @override
  String toString() => 'SetgreetPurchaseError(${code.rawValue}'
      '${providerCode != null ? ', providerCode: $providerCode' : ''}'
      '${message != null ? ', message: $message' : ''})';
}

/// What the SDK reports when a paywall screen has rendered its catalog.
@immutable
class SetgreetPaywallImpressionContext {
  const SetgreetPaywallImpressionContext({
    required this.flowId,
    required this.screenId,
    required this.source,
    required this.productRefs,
  });

  final String flowId;
  final String screenId;

  /// The screen's first source: its first plan picker's, else the default
  /// source.
  final SetgreetPurchaseSource source;

  /// The refs rendered on the screen, unique: the plan pickers' options in
  /// tree order, then fixed purchase-button refs, then refs quoted by
  /// `{{purchase.<ref>.*}}` tokens. Only refs the catalog has.
  final List<String> productRefs;

  @override
  String toString() =>
      'SetgreetPaywallImpressionContext(flowId: $flowId, screenId: $screenId, '
      'source: $source, productRefs: $productRefs)';
}

/// Implemented by the host app on top of its own purchase tool and
/// registered with `Setgreet.setPurchaseProvider`. Extend this class: the
/// optional methods then keep their default no-op bodies.
///
/// Every method is called by the native SDK, never by the dashboard:
/// - [loadProducts] when a paywall screen becomes current (a source that
///   loaded is not asked again in the flow session; a failed one is retried
///   by the next screen that reads it), and once at registration for the
///   default source.
/// - [purchase] and [restorePurchases] on a button tap.
/// - [accessState] when a paywall that carries `skipWhenAccess` becomes
///   current, after a successful catalog load of any other screen, after
///   purchase or restore outcomes that do not carry the access themselves,
///   and after the host's `identifyUser` has completed.
/// - [trackPaywallImpression] once per paywall screen per flow session, once
///   its catalog is in.
/// - [setAttributes] right before a purchase.
/// - [identify] and [reset] are optional and default to no-ops; implement
///   them only when Setgreet's `identifyUser` / `resetUser` should drive the
///   vendor identity.
///
/// All calls arrive on the root isolate. On a paywall screen the native SDK
/// waits up to 10 s for [loadProducts] (and for [accessState] when the screen
/// skips users who already have access) before the screen follows its
/// unavailable policy, and the plugin stops waiting for either after 30 s.
/// [purchase] and [restorePurchases] have no time limit, since a store sheet
/// can stay open for minutes. Neither have [identify] and [reset]: the native
/// SDK runs them one after another and writes the access attributes only
/// once they are done, so cutting a slow one short could attribute the
/// previous user's access to the new one.
abstract class SetgreetPurchaseProvider {
  const SetgreetPurchaseProvider();

  /// `"revenuecat"`, `"adapty"`, `"storekit"`, ... Must match
  /// `^[a-z][a-z0-9_]{0,39}$`: `Setgreet.setPurchaseProvider` throws a
  /// `SetgreetException` otherwise (the backend rejects a catalog sync from
  /// any other id).
  String get providerId;

  /// The products of [source], in the provider's order. Throw a
  /// [SetgreetPurchaseError] (`providerNotInitialized`, `productNotFound`,
  /// `networkError`, ...) when they cannot be loaded; any other error is
  /// reported as `unknown`.
  Future<List<SetgreetPurchaseProduct>> loadProducts(
      SetgreetPurchaseSource source);

  /// Buys the product [productRef] names in [source]. A ref is only unique
  /// within its source (`$rc_annual` exists in every RevenueCat offering):
  /// buy the product this provider returned for that ref from
  /// `loadProducts(source)`, never a product of the same ref from another
  /// source. Report the outcome as a status instead of throwing: a thrown
  /// [SetgreetPurchaseError] becomes `failed` with its code, anything else
  /// `failed` with `unknown`.
  Future<SetgreetPurchaseResult> purchase(
      String productRef, SetgreetPurchaseSource source);

  /// Restores earlier purchases. Report the outcome as a status instead of
  /// throwing: a thrown error becomes `failed`.
  Future<SetgreetRestoreResult> restorePurchases();

  /// What the user has access to right now; null when the provider cannot
  /// say (a thrown error counts as null too). A paywall that carries
  /// `skipWhenAccess` is skipped when this reports matching access, so
  /// answer for the current user only.
  Future<SetgreetPurchaseAccessState?> accessState();

  /// A paywall screen rendered its catalog. Optional, default no-op.
  void trackPaywallImpression(SetgreetPaywallImpressionContext context) {}

  /// Attribution attributes for the provider (`setgreet_flow`,
  /// `setgreet_screen`). Optional, default no-op.
  void setAttributes(Map<String, String> attributes) {}

  /// `Setgreet.identifyUser` was called. Optional, default no-op.
  Future<void> identify(String userId) async {}

  /// `Setgreet.resetUser` was called. Optional, default no-op.
  Future<void> reset() async {}
}
