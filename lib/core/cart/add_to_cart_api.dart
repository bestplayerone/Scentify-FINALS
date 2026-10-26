import 'package:cloud_functions/cloud_functions.dart';
import 'package:scentify/core/orders/my_purchases_api.dart';

class AddToCartApi {
  AddToCartApi({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: scentifyFunctionsRegion);

  final FirebaseFunctions _functions;

  Future<AddToCartResult> add({
    required String productId,
    required String variantId,
    int quantity = 1,
    String? operationId,
  }) async {
    if (quantity < 1 || quantity > 100) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Use a quantity from 1 to 100.',
      );
    }
    final result = await _functions
        .httpsCallable('addToCart')
        .call<Map<String, dynamic>>({
          'productId': productId,
          'variantId': variantId,
          'quantity': quantity,
          if (operationId != null && operationId.trim().isNotEmpty)
            'operationId': operationId.trim(),
        });
    return AddToCartResult.fromMap(result.data);
  }
}

class AddToCartResult {
  const AddToCartResult({
    required this.serverConfirmed,
    required this.noRedirect,
    required this.operationId,
    required this.updatedAt,
    required this.cartItemCount,
    required this.cartQuantity,
    this.item,
  });

  factory AddToCartResult.fromMap(Map<String, dynamic> data) {
    final serverConfirmed = data['serverConfirmed'];
    final noRedirect = data['noRedirect'];
    final operationId = data['operationId'];
    final updatedAt = data['updatedAt'];
    final cartItemCount = data['cartItemCount'];
    final cartQuantity = data['cartQuantity'];
    if (serverConfirmed != true ||
        noRedirect != true ||
        operationId is! String ||
        updatedAt is! String ||
        cartItemCount is! int ||
        cartQuantity is! int) {
      throw const FormatException('The add-to-cart response is invalid.');
    }
    final parsedDate = DateTime.tryParse(updatedAt);
    if (parsedDate == null) {
      throw const FormatException('The add-to-cart timestamp is invalid.');
    }
    final itemData = data['item'];
    return AddToCartResult(
      serverConfirmed: serverConfirmed,
      noRedirect: noRedirect,
      operationId: operationId,
      updatedAt: parsedDate,
      cartItemCount: cartItemCount,
      cartQuantity: cartQuantity,
      item: itemData is Map
          ? AddToCartItem.fromMap(
              itemData.map((key, value) => MapEntry(key.toString(), value)),
            )
          : null,
    );
  }

  final bool serverConfirmed;
  final bool noRedirect;
  final String operationId;
  final DateTime updatedAt;
  final int cartItemCount;
  final int cartQuantity;
  final AddToCartItem? item;
}

class AddToCartItem {
  const AddToCartItem({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.unitPriceCentavos,
    required this.quantity,
  });

  factory AddToCartItem.fromMap(Map<String, dynamic> data) {
    final values = [
      data['productId'],
      data['variantId'],
      data['productName'],
      data['variantLabel'],
      data['unitPriceCentavos'],
      data['quantity'],
    ];
    if (values[0] is! String ||
        values[1] is! String ||
        values[2] is! String ||
        values[3] is! String ||
        values[4] is! int ||
        values[5] is! int) {
      throw const FormatException('The add-to-cart item is invalid.');
    }
    return AddToCartItem(
      productId: values[0] as String,
      variantId: values[1] as String,
      productName: values[2] as String,
      variantLabel: values[3] as String,
      unitPriceCentavos: values[4] as int,
      quantity: values[5] as int,
    );
  }

  final String productId;
  final String variantId;
  final String productName;
  final String variantLabel;
  final int unitPriceCentavos;
  final int quantity;
}
