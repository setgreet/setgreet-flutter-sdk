// setgreet_revenuecat_provider.dart
//
// Reference `SetgreetPurchaseProvider` backed by RevenueCat.
//
// Targets: the Setgreet Flutter plugin with purchase providers, and RevenueCat
// purchases_flutter 10.3.0 or later, the first release with
// `CustomPaywallImpressionParams(offering:)` (10.2.x only has the `offeringId`
// form). Written and compiled against purchases_flutter 10.15.2.
//
// This file is meant to be COPIED into your app, not imported from a package:
// Setgreet ships no RevenueCat dependency and never configures it. Call
// `Purchases.configure(...)` yourself, then register one instance with
// `Setgreet.setPurchaseProvider(SetgreetRevenueCatProvider())`.
//
// Mapping:
//   product ref            RevenueCat package identifier ($rc_annual, $rc_monthly, custom);
//                          unique within its offering only, so packages are
//                          kept per (source, ref) and a purchase names its source
//   current_offering       Offerings.current
//   offering + sourceId    Offerings.getOffering(sourceId)
//   placement + sourceId   Purchases.getCurrentOfferingForPlacement(sourceId)
//   access refs            CustomerInfo.entitlements.active keys
//   title                  StoreProduct.title; on Google Play without the app
//                          name Play appends in parentheses
//   period                 StoreProduct.subscriptionPeriod (ISO 8601, e.g. P1M)
//   trial (App Store)      the introductory price, eligibility from
//                          checkTrialOrIntroductoryPriceEligibility
//   trial (Google Play)    the free (else intro) phase of the package's default option

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:setgreet/setgreet.dart';

class SetgreetRevenueCatProvider extends SetgreetPurchaseProvider {
  @override
  String get providerId => 'revenuecat';

  /// Packages by source, then by ref, kept between `loadProducts` and
  /// `purchase`: a package identifier such as `$rc_annual` exists in every
  /// offering, so a ref alone does not name a package. And the offering each
  /// source resolved to, for impression tracking.
  final Map<SetgreetPurchaseSource, Map<String, Package>> _packagesBySource =
      {};
  final Map<SetgreetPurchaseSource, Offering> _offeringsBySource = {};

  // Catalog

  @override
  Future<List<SetgreetPurchaseProduct>> loadProducts(
      SetgreetPurchaseSource source) async {
    final packages = (await _loadOffering(source)).availablePackages;
    final eligibility = await _introEligibility(packages);
    return [
      for (final package in packages)
        _product(package, eligibility[package.storeProduct.identifier]?.status),
    ];
  }

  /// Fetches the offering [source] resolves to and keeps its packages under
  /// that source, for [purchase].
  Future<Offering> _loadOffering(SetgreetPurchaseSource source) async {
    if (!await Purchases.isConfigured) {
      throw const SetgreetPurchaseError(
        code: SetgreetPurchaseErrorCode.providerNotInitialized,
        message: 'Purchases.configure(...) has not been called',
      );
    }

    final Offering? offering;
    try {
      offering = await _offering(source);
    } on PlatformException catch (error) {
      throw _normalizedError(error, SetgreetPurchaseErrorCode.networkError);
    }
    if (offering == null) {
      throw SetgreetPurchaseError(
        code: SetgreetPurchaseErrorCode.productNotFound,
        message:
            'No offering for ${source.sourceType} ${source.sourceId ?? ''}',
      );
    }

    // The first package of an identifier wins, as RevenueCat lists them.
    final packages = <String, Package>{};
    for (final package in offering.availablePackages) {
      packages.putIfAbsent(package.identifier, () => package);
    }
    _packagesBySource[source] = packages;
    _offeringsBySource[source] = offering;
    return offering;
  }

  Future<Offering?> _offering(SetgreetPurchaseSource source) async {
    final id = source.sourceId;
    switch (source.sourceType) {
      case 'offering':
        return id == null
            ? null
            : (await Purchases.getOfferings()).getOffering(id);
      case 'placement':
        return id == null
            ? null
            : await Purchases.getCurrentOfferingForPlacement(id);
      default:
        return (await Purchases.getOfferings()).current;
    }
  }

  /// App Store only: whether this user can take each product's introductory
  /// offer. Google Play needs no call (see [_playIntroOffer]), and RevenueCat
  /// answers "unknown" there anyway.
  Future<Map<String, IntroEligibility>> _introEligibility(
      List<Package> packages) async {
    if (_onGooglePlay) return const {};
    try {
      return await Purchases.checkTrialOrIntroductoryPriceEligibility(
        [for (final package in packages) package.storeProduct.identifier],
      );
    } catch (_) {
      // Best effort: unknown eligibility, so the SDK shows no trial text.
      return const {};
    }
  }

  // Purchase

  @override
  Future<SetgreetPurchaseResult> purchase(
      String productRef, SetgreetPurchaseSource source) async {
    if (!await Purchases.isConfigured) {
      return SetgreetPurchaseResult(
        status: SetgreetPurchaseStatus.failed,
        productRef: productRef,
        error: const SetgreetPurchaseError(
            code: SetgreetPurchaseErrorCode.providerNotInitialized),
      );
    }
    final Package package;
    try {
      package = await _resolvePackage(productRef, source);
    } on SetgreetPurchaseError catch (error) {
      return SetgreetPurchaseResult(
        status: SetgreetPurchaseStatus.failed,
        productRef: productRef,
        error: error,
      );
    }

    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return SetgreetPurchaseResult(
        status: SetgreetPurchaseStatus.purchased,
        productRef: productRef,
        accessRefs: _accessRefs(result.customerInfo),
      );
    } on PlatformException catch (error) {
      final ownedAccessRefs =
          _errorCode(error) == PurchasesErrorCode.productAlreadyPurchasedError
              ? await _activeAccessRefs()
              : null;
      return _purchaseFailure(error, productRef, ownedAccessRefs);
    }
  }

  /// The result of a purchase RevenueCat refused with [error].
  ///
  /// `productAlreadyPurchasedError` is how RevenueCat reports Google Play's
  /// `ITEM_ALREADY_OWNED`: the store account already owns the product, e.g. a
  /// subscriber who reached the paywall anyway. When RevenueCat confirms an
  /// active entitlement ([ownedAccessRefs] not empty) the user already has
  /// what they tapped for, so it is reported as purchased and the flow moves
  /// on, instead of a generic error under the button. Without one (the
  /// purchase belongs to another app user, or is not synced yet) it stays a
  /// failure.
  SetgreetPurchaseResult _purchaseFailure(
    PlatformException error,
    String productRef,
    List<String>? ownedAccessRefs,
  ) {
    final details = error.details;
    if (details is Map && details['userCancelled'] == true) {
      return SetgreetPurchaseResult(
        status: SetgreetPurchaseStatus.cancelled,
        productRef: productRef,
      );
    }
    if (_errorCode(error) == PurchasesErrorCode.productAlreadyPurchasedError &&
        ownedAccessRefs != null &&
        ownedAccessRefs.isNotEmpty) {
      return SetgreetPurchaseResult(
        status: SetgreetPurchaseStatus.purchased,
        productRef: productRef,
        accessRefs: ownedAccessRefs,
      );
    }
    final normalized =
        _normalizedError(error, SetgreetPurchaseErrorCode.purchaseFailed);
    final status = switch (normalized.code) {
      SetgreetPurchaseErrorCode.purchaseCancelled =>
        SetgreetPurchaseStatus.cancelled,
      SetgreetPurchaseErrorCode.purchasePending =>
        SetgreetPurchaseStatus.pending,
      _ => SetgreetPurchaseStatus.failed,
    };
    return SetgreetPurchaseResult(
      status: status,
      productRef: productRef,
      error: normalized,
    );
  }

  /// The user's active entitlements as RevenueCat reports them now; null when
  /// it cannot say.
  Future<List<String>?> _activeAccessRefs() async {
    try {
      return _accessRefs(await Purchases.getCustomerInfo());
    } on PlatformException {
      return null;
    }
  }

  /// The package [ref] names in [source], never one of the same ref from
  /// another offering. A cold cache (no `loadProducts(source)` yet in this
  /// process) loads that source's offering first.
  Future<Package> _resolvePackage(
      String ref, SetgreetPurchaseSource source) async {
    final cached = _packagesBySource[source]?[ref];
    if (cached != null) return cached;
    try {
      await _loadOffering(source);
    } on SetgreetPurchaseError {
      rethrow;
    } catch (error) {
      throw SetgreetPurchaseError(
        code: SetgreetPurchaseErrorCode.unknown,
        message: error.toString(),
      );
    }
    final loaded = _packagesBySource[source]?[ref];
    if (loaded == null) {
      throw SetgreetPurchaseError(
        code: SetgreetPurchaseErrorCode.productNotFound,
        message:
            'No package $ref in ${source.sourceType} ${source.sourceId ?? ''}',
      );
    }
    return loaded;
  }

  // Restore

  @override
  Future<SetgreetRestoreResult> restorePurchases() async {
    if (!await Purchases.isConfigured) {
      return const SetgreetRestoreResult(
        status: SetgreetRestoreStatus.failed,
        error: SetgreetPurchaseError(
            code: SetgreetPurchaseErrorCode.providerNotInitialized),
      );
    }
    try {
      final refs = _accessRefs(await Purchases.restorePurchases());
      return SetgreetRestoreResult(
        status: refs.isEmpty
            ? SetgreetRestoreStatus.nothingToRestore
            : SetgreetRestoreStatus.restored,
        accessRefs: refs,
      );
    } on PlatformException catch (error) {
      return SetgreetRestoreResult(
        status: SetgreetRestoreStatus.failed,
        error: _normalizedError(error, SetgreetPurchaseErrorCode.restoreFailed),
      );
    }
  }

  // Access

  @override
  Future<SetgreetPurchaseAccessState?> accessState() async {
    if (!await Purchases.isConfigured) return null;
    final CustomerInfo info;
    try {
      info = await Purchases.getCustomerInfo();
    } on PlatformException {
      return null;
    }
    final refs = _accessRefs(info);
    return SetgreetPurchaseAccessState(
        active: refs.isNotEmpty, accessRefs: refs);
  }

  // Attribution

  @override
  void trackPaywallImpression(SetgreetPaywallImpressionContext context) {
    final offering = _offeringsBySource[context.source];
    unawaited(_whenConfigured(() => Purchases.trackCustomPaywallImpression(
          params: CustomPaywallImpressionParams(
            paywallId: context.screenId,
            offering: offering,
          ),
        )));
  }

  @override
  void setAttributes(Map<String, String> attributes) {
    unawaited(_whenConfigured(() => Purchases.setAttributes(attributes)));
  }

  /// Runs [call] when RevenueCat is configured. Attribution is best effort:
  /// a failure is dropped.
  Future<void> _whenConfigured(Future<void> Function() call) async {
    try {
      if (await Purchases.isConfigured) await call();
    } catch (_) {
      // Nothing to report: the paywall works without it.
    }
  }

  // `identify(userId)` and `reset()` keep their default no-ops on purpose:
  // the host app already drives `Purchases.logIn` / `Purchases.logOut`, and a
  // second caller can merge or switch RevenueCat identities by accident.

  // Mapping

  /// Android stores are Google Play here; the App Store otherwise.
  bool get _onGooglePlay => defaultTargetPlatform == TargetPlatform.android;

  SetgreetPurchaseProduct _product(
      Package package, IntroEligibilityStatus? eligibility) {
    final storeProduct = package.storeProduct;
    return SetgreetPurchaseProduct(
      ref: package.identifier,
      storeProductId: storeProduct.identifier,
      title: _onGooglePlay
          ? playProductName(storeProduct.title)
          : storeProduct.title,
      description: storeProduct.description,
      localizedPrice: storeProduct.priceString,
      priceAmount: storeProduct.price,
      currencyCode: storeProduct.currencyCode,
      period: _period(storeProduct.subscriptionPeriod),
      introOffer: _onGooglePlay
          ? _playIntroOffer(storeProduct)
          : _appStoreIntroOffer(storeProduct, eligibility),
    );
  }

  /// Google Play's product title without the app name Play appends in
  /// parentheses: "Premium Annual (Your App)" -> "Premium Annual".
  ///
  /// purchases_flutter maps `title` from Play's title, which carries the app
  /// name, and has no `name` (the Kotlin reference reads `name`). Scans back
  /// from the final ")" to its matching "(", so the product's own
  /// parentheses survive ("Pro (Annual) (Your App)" -> "Pro (Annual)") and a
  /// nested app name goes as a whole ("Pro (Your App (Beta))" -> "Pro"). A
  /// title that does not end in a balanced group, or that is nothing but the
  /// group, is returned unchanged.
  @visibleForTesting
  static String playProductName(String title) {
    final trimmed = title.trimRight();
    if (!trimmed.endsWith(')')) return title;
    var depth = 0;
    for (var i = trimmed.length - 1; i >= 0; i--) {
      final character = trimmed[i];
      if (character == ')') {
        depth++;
      } else if (character == '(') {
        depth--;
        if (depth == 0) {
          final name = trimmed.substring(0, i).trimRight();
          return name.isEmpty ? title : name;
        }
      }
    }
    return title;
  }

  /// `P1W`, `P1M`, `P3M`, `P1Y`: the store's ISO 8601 subscription period.
  /// null for a one-time purchase.
  static SetgreetPurchasePeriod? _period(String? iso8601) {
    final match = RegExp(r'^P(\d+)([DWMY])$').firstMatch(iso8601 ?? '');
    if (match == null) return null;
    final unit = switch (match.group(2)) {
      'D' => SetgreetPurchasePeriodUnit.day,
      'W' => SetgreetPurchasePeriodUnit.week,
      'M' => SetgreetPurchasePeriodUnit.month,
      _ => SetgreetPurchasePeriodUnit.year,
    };
    return SetgreetPurchasePeriod(
        unit: unit, count: int.parse(match.group(1)!));
  }

  /// App Store: the product's introductory offer, eligible as RevenueCat
  /// reports it.
  ///
  /// purchases_flutter does not expose StoreKit's payment mode, so the type
  /// is derived from the offer: free is a trial; a paid offer over several
  /// periods is pay-as-you-go, over one period pay-up-front. A known
  /// approximation: a one-period pay-as-you-go offer reads as `payUpFront`.
  /// The type of a paid offer is catalog metadata only; the SDK derives
  /// `trialText` from trials alone, so the trial text is unaffected.
  SetgreetPurchaseIntroOffer? _appStoreIntroOffer(
      StoreProduct storeProduct, IntroEligibilityStatus? eligibility) {
    final intro = storeProduct.introductoryPrice;
    if (intro == null) return null;
    return SetgreetPurchaseIntroOffer(
      type: intro.price == 0
          ? SetgreetPurchaseIntroOffer.trialType
          : intro.cycles > 1
              ? 'payAsYouGo'
              : 'payUpFront',
      localizedPrice: intro.priceString,
      periodText: _periodText(intro.periodUnit, intro.periodNumberOfUnits),
      eligible: _eligible(eligibility),
    );
  }

  /// Google Play: the trial (else the intro price) of the option a package
  /// purchase uses, its default option.
  ///
  /// Eligibility: Google Play hands an app only the offers the current user
  /// is eligible for, so an offer present here is one the user can take.
  /// RevenueCat: "The subscriptionOptions contain only offers that the
  /// current customer is eligible for"
  /// (https://www.revenuecat.com/docs/subscription-guidance/subscription-offers).
  /// A user who already used the trial gets the base plan as the default
  /// option, which has no free or intro phase.
  SetgreetPurchaseIntroOffer? _playIntroOffer(StoreProduct storeProduct) {
    final option = storeProduct.defaultOption;
    final phase = option?.freePhase ?? option?.introPhase;
    if (phase == null) return null;
    // null for a phase that is not an offer (the dashboard knows these
    // three types only).
    final type = switch (phase.offerPaymentMode) {
      OfferPaymentMode.freeTrial => SetgreetPurchaseIntroOffer.trialType,
      OfferPaymentMode.singlePayment => 'payUpFront',
      OfferPaymentMode.discountedRecurringPayment => 'payAsYouGo',
      _ => null,
    };
    if (type == null) return null;
    final period = phase.billingPeriod;
    return SetgreetPurchaseIntroOffer(
      type: type,
      localizedPrice: phase.price.formatted,
      periodText:
          period == null ? null : _periodText(period.unit, period.value),
      eligible: true,
    );
  }

  /// `7 days`, `1 week`: what the SDK turns into `7-day free trial`.
  static String _periodText(PeriodUnit unit, int value) {
    final name = switch (unit) {
      PeriodUnit.day => 'day',
      PeriodUnit.week => 'week',
      PeriodUnit.month => 'month',
      PeriodUnit.year => 'year',
      _ => 'period',
    };
    return '$value $name${value == 1 ? '' : 's'}';
  }

  /// null when RevenueCat could not determine eligibility (missing
  /// subscription group info); the SDK then shows no trial text, which it
  /// derives only for a user reported as eligible.
  static bool? _eligible(IntroEligibilityStatus? status) => switch (status) {
        IntroEligibilityStatus.introEligibilityStatusEligible => true,
        IntroEligibilityStatus.introEligibilityStatusIneligible ||
        IntroEligibilityStatus.introEligibilityStatusNoIntroOfferExists =>
          false,
        _ => null,
      };

  static List<String> _accessRefs(CustomerInfo info) =>
      info.entitlements.active.keys.toList()..sort();

  /// RevenueCat's error code; null for an error that did not come from
  /// RevenueCat (its codes are numeric).
  static PurchasesErrorCode? _errorCode(PlatformException error) {
    final code = int.tryParse(error.code);
    if (code == null || code < 0) return null;
    return PurchasesErrorHelper.getErrorCode(error);
  }

  /// RevenueCat's `PurchasesErrorCode` -> the normalized code; the vendor's
  /// code name travels as `providerCode` for logs and analytics.
  static SetgreetPurchaseError _normalizedError(
      PlatformException error, SetgreetPurchaseErrorCode fallback) {
    final code = _errorCode(error);
    if (code == null) {
      return SetgreetPurchaseError(code: fallback, message: error.message);
    }
    final normalized = switch (code) {
      PurchasesErrorCode.purchaseCancelledError =>
        SetgreetPurchaseErrorCode.purchaseCancelled,
      PurchasesErrorCode.paymentPendingError =>
        SetgreetPurchaseErrorCode.purchasePending,
      PurchasesErrorCode.productNotAvailableForPurchaseError =>
        SetgreetPurchaseErrorCode.productUnavailable,
      PurchasesErrorCode.networkError ||
      PurchasesErrorCode.offlineConnectionError =>
        SetgreetPurchaseErrorCode.networkError,
      PurchasesErrorCode.invalidAppUserIdError =>
        SetgreetPurchaseErrorCode.identityError,
      PurchasesErrorCode.configurationError =>
        SetgreetPurchaseErrorCode.notConfigured,
      _ => fallback,
    };
    return SetgreetPurchaseError(
      code: normalized,
      providerCode: code.name,
      message: error.message,
    );
  }
}
