import 'package:flutter_test/flutter_test.dart';
import 'package:setgreet/setgreet.dart';

void main() {
  test('error codes carry the contract raw values (PAYWALL_PROVIDERS.md 2.11)',
      () {
    expect(
      {
        for (final code in SetgreetPurchaseErrorCode.values) code: code.rawValue
      },
      {
        SetgreetPurchaseErrorCode.notConfigured: 'not_configured',
        SetgreetPurchaseErrorCode.providerNotInitialized:
            'provider_not_initialized',
        SetgreetPurchaseErrorCode.productNotFound: 'product_not_found',
        SetgreetPurchaseErrorCode.productUnavailable: 'product_unavailable',
        SetgreetPurchaseErrorCode.purchaseCancelled: 'purchase_cancelled',
        SetgreetPurchaseErrorCode.purchaseFailed: 'purchase_failed',
        SetgreetPurchaseErrorCode.purchasePending: 'purchase_pending',
        SetgreetPurchaseErrorCode.restoreFailed: 'restore_failed',
        SetgreetPurchaseErrorCode.networkError: 'network_error',
        SetgreetPurchaseErrorCode.identityError: 'identity_error',
        SetgreetPurchaseErrorCode.unknown: 'unknown',
      },
    );
  });

  test('fromRawValue maps every raw value back and anything else to unknown',
      () {
    for (final code in SetgreetPurchaseErrorCode.values) {
      expect(SetgreetPurchaseErrorCode.fromRawValue(code.rawValue), code);
    }
    expect(SetgreetPurchaseErrorCode.fromRawValue('networkError'),
        SetgreetPurchaseErrorCode.unknown);
    expect(SetgreetPurchaseErrorCode.fromRawValue(null),
        SetgreetPurchaseErrorCode.unknown);
  });

  test('statuses carry the Response Split values', () {
    expect(SetgreetPurchaseStatus.values.map((s) => s.rawValue),
        ['purchased', 'cancelled', 'failed', 'pending']);
    expect(SetgreetRestoreStatus.values.map((s) => s.rawValue),
        ['restored', 'nothingToRestore', 'failed']);
    expect(SetgreetPurchasePeriodUnit.values.map((u) => u.rawValue),
        ['day', 'week', 'month', 'year']);
  });

  test('sources: the three kinds, compared by value', () {
    const current = SetgreetPurchaseSource.currentOffering();
    expect(current.sourceType, 'current_offering');
    expect(current.sourceId, isNull);

    const offering = SetgreetPurchaseSource.offering('discount');
    expect(offering.sourceType, 'offering');
    expect(offering.sourceId, 'discount');

    const placement = SetgreetPurchaseSource.placement('onboarding');
    expect(placement.sourceType, 'placement');
    expect(placement.sourceId, 'onboarding');

    expect(
      const SetgreetPurchaseSource(
          sourceType: 'offering', sourceId: 'discount'),
      offering,
    );
    expect(offering, isNot(const SetgreetPurchaseSource.placement('discount')));
    expect({offering: 1}[const SetgreetPurchaseSource.offering('discount')], 1);
  });

  test('a product price must be finite (debug assert)', () {
    SetgreetPurchaseProduct product(double priceAmount) =>
        SetgreetPurchaseProduct(
          ref: r'$rc_annual',
          storeProductId: 'com.app.annual',
          localizedPrice: r'$49.99',
          priceAmount: priceAmount,
          currencyCode: 'USD',
        );

    expect(product(49.99).priceAmount, 49.99);
    expect(product(0).priceAmount, 0);
    expect(() => product(double.nan), throwsAssertionError);
    expect(() => product(double.infinity), throwsAssertionError);
    expect(() => product(double.negativeInfinity), throwsAssertionError);
  });

  test('results default to no access refs and no error', () {
    const result = SetgreetPurchaseResult(
        status: SetgreetPurchaseStatus.cancelled, productRef: r'$rc_annual');
    expect(result.accessRefs, isEmpty);
    expect(result.error, isNull);

    const restore =
        SetgreetRestoreResult(status: SetgreetRestoreStatus.nothingToRestore);
    expect(restore.accessRefs, isEmpty);
    expect(restore.error, isNull);
  });
}
