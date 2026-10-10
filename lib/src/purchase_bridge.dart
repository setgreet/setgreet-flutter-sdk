// The Dart end of the purchase bridge. Internal: not exported from
// `package:setgreet/setgreet.dart`.
//
// The native SDKs call the host's purchase provider. In a Flutter app that
// provider is a Dart object, so the plugin registers a native proxy provider
// whose methods invoke `setgreet/purchases` on the main thread; this handler
// answers each call from the registered [SetgreetPurchaseProvider].
//
// Protocol (native -> Dart, one method per provider method):
//   loadProducts            {source}                 -> [product map, ...]
//   purchase                {productRef, source}     -> result map
//   restorePurchases        null                     -> restore result map
//   accessState             null                     -> {active, accessRefs} | null
//   trackPaywallImpression  {flowId, screenId, source, productRefs} -> null
//   setAttributes           {attributes}             -> null
//   identify                {userId}                 -> null
//   reset                   null                     -> null
// A source is {sourceType, sourceId}. An unknown method answers
// "not implemented", which the native proxy treats like a missing provider.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'purchases.dart';

/// One `setPurchaseProvider` call, from [SetgreetPurchaseBridge.begin] until
/// the native side accepted or rejected it.
class PurchaseRegistration {
  PurchaseRegistration._(this.provider, this.firstInIsolate);

  final SetgreetPurchaseProvider provider;

  /// What the registration tells the native side as `firstInIsolate`.
  final bool firstInIsolate;
}

class SetgreetPurchaseBridge {
  SetgreetPurchaseBridge._();

  /// The channel the native proxy provider invokes.
  static const MethodChannel channel = MethodChannel('setgreet/purchases');

  /// The provider the native side accepted.
  static SetgreetPurchaseProvider? _provider;

  /// The latest registration in flight. Its provider answers native calls
  /// meanwhile: the native side starts loading the default source through
  /// it before the registration call returns.
  static PurchaseRegistration? _pending;

  static bool _registeredInThisIsolate = false;

  /// The in-flight registration that claimed to be the isolate's first.
  static PurchaseRegistration? _firstInFlight;

  /// Whether a registration begun now would be the first of this isolate:
  /// none was accepted yet and none that claimed it is in flight. The native
  /// side answers every call it is still waiting on with its fallback when a
  /// registration is the first: such a call went to an isolate that no longer
  /// exists (a hot restart), so its reply would never come and a paywall
  /// button could stay locked. Only one registration claims it, so a second
  /// one in flight does not cancel the first one's catalog preload.
  static bool get isFirstRegistration =>
      !_registeredInThisIsolate && _firstInFlight == null;

  /// Starts registering [provider]: from now on it answers native calls.
  /// Call before the native registration, send the returned registration's
  /// [PurchaseRegistration.firstInIsolate], then [commit] or [abandon] it.
  static PurchaseRegistration begin(SetgreetPurchaseProvider provider) {
    final registration = PurchaseRegistration._(provider, isFirstRegistration);
    if (registration.firstInIsolate) _firstInFlight = registration;
    _pending = registration;
    channel.setMethodCallHandler(handleMethodCall);
    return registration;
  }

  /// The native side accepted [registration].
  static void commit(PurchaseRegistration registration) {
    _provider = registration.provider;
    if (identical(_pending, registration)) _pending = null;
    if (identical(_firstInFlight, registration)) _firstInFlight = null;
    _registeredInThisIsolate = true;
  }

  /// The native side rejected [registration]: the provider accepted before
  /// it, if any, answers again, and a later registration may claim to be the
  /// first.
  static void abandon(PurchaseRegistration registration) {
    if (identical(_pending, registration)) _pending = null;
    if (identical(_firstInFlight, registration)) _firstInFlight = null;
  }

  /// Forgets every registration. Tests only.
  @visibleForTesting
  static void debugReset() {
    _provider = null;
    _pending = null;
    _registeredInThisIsolate = false;
    _firstInFlight = null;
    channel.setMethodCallHandler(null);
  }

  /// Answers one native call. Never lets a provider error escape, except
  /// from `loadProducts`, whose error the native side rethrows.
  @visibleForTesting
  static Future<Object?> handleMethodCall(MethodCall call) async {
    final provider = _pending?.provider ?? _provider;
    if (provider == null) {
      throw MissingPluginException('No SetgreetPurchaseProvider is registered');
    }
    final arguments = call.arguments is Map ? call.arguments as Map : const {};

    switch (call.method) {
      case 'loadProducts':
        return _loadProducts(provider, decodeSource(arguments['source']));
      case 'purchase':
        return _purchase(
          provider,
          _string(arguments['productRef']),
          decodeSource(arguments['source']),
        );
      case 'restorePurchases':
        return _restorePurchases(provider);
      case 'accessState':
        return _accessState(provider);
      case 'trackPaywallImpression':
        try {
          provider.trackPaywallImpression(SetgreetPaywallImpressionContext(
            flowId: _string(arguments['flowId']),
            screenId: _string(arguments['screenId']),
            source: decodeSource(arguments['source']),
            productRefs: _stringList(arguments['productRefs']),
          ));
        } catch (_) {
          // Fire-and-forget: a provider error must not reach the native side.
        }
        return null;
      case 'setAttributes':
        try {
          provider.setAttributes(_stringMap(arguments['attributes']));
        } catch (_) {
          // Fire-and-forget, as above.
        }
        return null;
      case 'identify':
        try {
          await provider.identify(_string(arguments['userId']));
        } catch (_) {
          // The native side only waits for it to finish.
        }
        return null;
      case 'reset':
        try {
          await provider.reset();
        } catch (_) {
          // As above.
        }
        return null;
      default:
        throw MissingPluginException(
            'Unknown purchase bridge method ${call.method}');
    }
  }

  static Future<List<Map<String, Object?>>> _loadProducts(
    SetgreetPurchaseProvider provider,
    SetgreetPurchaseSource source,
  ) async {
    final List<SetgreetPurchaseProduct> products;
    try {
      products = await provider.loadProducts(source);
    } on SetgreetPurchaseError catch (error) {
      throw PlatformException(
        code: error.code.rawValue,
        message: error.message,
        details: <String, Object?>{'providerCode': error.providerCode},
      );
    } catch (error) {
      throw PlatformException(
        code: SetgreetPurchaseErrorCode.unknown.rawValue,
        message: error.toString(),
      );
    }
    return products.map(encodeProduct).toList();
  }

  static Future<Map<String, Object?>> _purchase(
    SetgreetPurchaseProvider provider,
    String productRef,
    SetgreetPurchaseSource source,
  ) async {
    try {
      return encodePurchaseResult(await provider.purchase(productRef, source));
    } catch (error) {
      return encodePurchaseResult(SetgreetPurchaseResult(
        status: SetgreetPurchaseStatus.failed,
        productRef: productRef,
        error: _asPurchaseError(error),
      ));
    }
  }

  static Future<Map<String, Object?>> _restorePurchases(
    SetgreetPurchaseProvider provider,
  ) async {
    try {
      return encodeRestoreResult(await provider.restorePurchases());
    } catch (error) {
      return encodeRestoreResult(SetgreetRestoreResult(
        status: SetgreetRestoreStatus.failed,
        error: _asPurchaseError(error),
      ));
    }
  }

  static Future<Map<String, Object?>?> _accessState(
    SetgreetPurchaseProvider provider,
  ) async {
    try {
      final access = await provider.accessState();
      if (access == null) return null;
      return <String, Object?>{
        'active': access.active,
        'accessRefs': List<String>.of(access.accessRefs),
      };
    } catch (_) {
      // "Cannot say", like the provider's own null.
      return null;
    }
  }

  /// A thrown [SetgreetPurchaseError] keeps its code; anything else is
  /// `unknown` with the error's description.
  static SetgreetPurchaseError _asPurchaseError(Object error) {
    if (error is SetgreetPurchaseError) return error;
    return SetgreetPurchaseError(
      code: SetgreetPurchaseErrorCode.unknown,
      message: error.toString(),
    );
  }

  // MARK: - Codec

  /// A source as it crosses the channel.
  static Map<String, Object?> encodeSource(SetgreetPurchaseSource source) =>
      <String, Object?>{
        'sourceType': source.sourceType,
        'sourceId': source.sourceId,
      };

  /// A source from the channel; the current offering when absent.
  static SetgreetPurchaseSource decodeSource(Object? value) {
    if (value is! Map) return const SetgreetPurchaseSource.currentOffering();
    final sourceType = value['sourceType'];
    final sourceId = value['sourceId'];
    return SetgreetPurchaseSource(
      sourceType: sourceType is String ? sourceType : 'current_offering',
      sourceId: sourceId is String ? sourceId : null,
    );
  }

  /// `priceAmount` crosses as a double; the native side converts it to an
  /// exact decimal through its shortest decimal form.
  static Map<String, Object?> encodeProduct(SetgreetPurchaseProduct product) =>
      <String, Object?>{
        'ref': product.ref,
        'storeProductId': product.storeProductId,
        'title': product.title,
        'description': product.description,
        'localizedPrice': product.localizedPrice,
        'priceAmount': product.priceAmount,
        'currencyCode': product.currencyCode,
        'period': product.period == null
            ? null
            : <String, Object?>{
                'unit': product.period!.unit.rawValue,
                'count': product.period!.count,
              },
        'introOffer': product.introOffer == null
            ? null
            : <String, Object?>{
                'type': product.introOffer!.type,
                'localizedPrice': product.introOffer!.localizedPrice,
                'periodText': product.introOffer!.periodText,
                'eligible': product.introOffer!.eligible,
              },
      };

  static Map<String, Object?> encodePurchaseResult(
          SetgreetPurchaseResult result) =>
      <String, Object?>{
        'status': result.status.rawValue,
        'productRef': result.productRef,
        'accessRefs': List<String>.of(result.accessRefs),
        'error': encodeError(result.error),
      };

  static Map<String, Object?> encodeRestoreResult(
          SetgreetRestoreResult result) =>
      <String, Object?>{
        'status': result.status.rawValue,
        'accessRefs': List<String>.of(result.accessRefs),
        'error': encodeError(result.error),
      };

  static Map<String, Object?>? encodeError(SetgreetPurchaseError? error) =>
      error == null
          ? null
          : <String, Object?>{
              'code': error.code.rawValue,
              'providerCode': error.providerCode,
              'message': error.message,
            };

  static String _string(Object? value) => value is String ? value : '';

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const <String>[];

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const <String, String>{};
    final result = <String, String>{};
    value.forEach((key, entry) {
      if (key is String && entry is String) result[key] = entry;
    });
    return result;
  }
}
