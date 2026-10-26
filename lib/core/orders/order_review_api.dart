import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:scentify/core/firebase/firestore_codecs.dart';
import 'package:scentify/core/orders/my_purchases_api.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/checkout/domain/models/checkout_quote.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/checkout/domain/services/checkout_review_provider.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

class OrderReviewApi
    implements CheckoutReviewProvider, CashOnDeliveryOrderProvider {
  OrderReviewApi({FirebaseFunctions? functions, FirebaseFirestore? firestore})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: scentifyFunctionsRegion),
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  @override
  Future<Order> createCashOnDeliveryOrder({
    required String orderId,
    required String userId,
    required ShippingAddress shippingAddress,
    required DeliveryOption deliveryOption,
  }) async {
    final result = await _functions
        .httpsCallable('createCashOnDeliveryOrder')
        .call<Map<String, dynamic>>({'orderId': orderId});
    final response = result.data;
    if (response['orderId'] != orderId ||
        response['userId'] != userId ||
        response['paymentMethod'] != 'cod' ||
        !const {
          'pending_collection',
          'unpaid',
          'paid',
        }.contains(response['paymentStatus'])) {
      throw const FormatException(
        'The server did not confirm the cash-on-delivery order.',
      );
    }
    final document = await _firestore.collection('orders').doc(orderId).get();
    final data = document.data();
    if (!document.exists || data == null) {
      throw const FormatException(
        'The confirmed order could not be loaded. Retry to check its status.',
      );
    }
    return FirestoreCodecs.orderFromMap(data, id: orderId);
  }

  @override
  Future<CheckoutQuote> createQuote({
    required String orderId,
    required String userId,
    required List<CartItem> selectedItems,
    required ShippingAddress shippingAddress,
    required DeliveryOption deliveryOption,
    required String paymentMethod,
    String? addressId,
  }) async {
    final payload = await build(
      orderId: orderId,
      deliveryOptionId: deliveryOption.id,
      paymentMethod: paymentMethod,
      addressId: addressId,
      shippingAddress: addressId == null
          ? {
              'fullName': shippingAddress.fullName,
              'phoneNumber': shippingAddress.phoneNumber,
              'addressLine1': shippingAddress.addressLine1,
              'barangay': shippingAddress.barangay,
              'city': shippingAddress.city,
              'province': shippingAddress.province,
              'postalCode': shippingAddress.postalCode,
              'notes': shippingAddress.notes,
            }
          : null,
      selectedItems: [
        for (final item in selectedItems)
          {
            'productId': item.productId,
            'variantId': item.variantId,
            'quantity': item.quantity,
          },
      ],
    );
    if (payload.orderId != orderId ||
        payload.userId != userId ||
        payload.status != 'ready_for_place_order' ||
        payload.payment['method'] != paymentMethod ||
        payload.deliveryOptionSnapshot['id'] != deliveryOption.id ||
        !payload.expiresAt.isAfter(DateTime.now())) {
      throw const FormatException(
        'The server order review is no longer valid.',
      );
    }

    final address = payload.shippingAddressSnapshot;
    final delivery = payload.deliveryOptionSnapshot;
    final pricing = payload.pricing;
    return CheckoutQuote(
      orderId: payload.orderId,
      userId: payload.userId,
      items: [
        for (final item in payload.items)
          CheckoutQuoteItem(
            productId: item.productId,
            variantId: item.variantId,
            productName: item.productName,
            variantLabel: item.variantLabel,
            unitPrice: Money(item.unitPriceCentavos),
            quantity: item.quantity,
          ),
      ],
      shippingAddress: ShippingAddress(
        fullName: _string(address['fullName'], 'shippingAddress.fullName'),
        phoneNumber: _string(
          address['phoneNumber'],
          'shippingAddress.phoneNumber',
        ),
        addressLine1: _string(
          address['addressLine1'],
          'shippingAddress.addressLine1',
        ),
        barangay: _string(address['barangay'], 'shippingAddress.barangay'),
        city: _string(address['city'], 'shippingAddress.city'),
        province: _string(address['province'], 'shippingAddress.province'),
        postalCode: _string(
          address['postalCode'],
          'shippingAddress.postalCode',
        ),
        notes: _optionalString(address['notes']),
      ),
      deliveryOption: DeliveryOption(
        id: _string(delivery['id'], 'deliveryOption.id'),
        name: _string(delivery['name'], 'deliveryOption.name'),
        fee: Money(
          _integer(delivery['feeCentavos'], 'deliveryOption.feeCentavos'),
        ),
        estimatedDays: _string(
          delivery['estimatedDays'],
          'deliveryOption.estimatedDays',
        ),
      ),
      subtotal: Money(
        _integer(pricing['subtotalCentavos'], 'pricing.subtotalCentavos'),
      ),
      total: Money(_integer(pricing['totalCentavos'], 'pricing.totalCentavos')),
    );
  }

  Future<OrderReviewPayload> build({
    String? orderId,
    required String deliveryOptionId,
    required String paymentMethod,
    String? addressId,
    Map<String, dynamic>? shippingAddress,
    List<Map<String, dynamic>>? selectedItems,
  }) async {
    final payload = <String, dynamic>{
      'deliveryOptionId': deliveryOptionId,
      'paymentMethod': paymentMethod,
      'currency': 'PHP',
    };
    if (orderId != null) payload['orderId'] = orderId;
    if (selectedItems != null) payload['selectedItems'] = selectedItems;
    if (addressId != null) payload['addressId'] = addressId;
    if (shippingAddress != null) payload['shippingAddress'] = shippingAddress;
    final result = await _functions
        .httpsCallable('getOrderReview')
        .call<Map<String, dynamic>>(payload);
    return OrderReviewPayload.fromMap(result.data);
  }
}

String _optionalString(Object? value) => value is String ? value : '';

int _integer(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('Expected $field to be an integer.');
}

class OrderReviewPayload {
  const OrderReviewPayload({
    required this.orderId,
    required this.userId,
    required this.status,
    required this.serverCalculated,
    required this.currency,
    required this.shippingAddressSnapshot,
    required this.deliveryOptionSnapshot,
    required this.payment,
    required this.items,
    required this.pricing,
    required this.createdAt,
    required this.expiresAt,
    required this.acknowledgement,
  });

  factory OrderReviewPayload.fromMap(Map<String, dynamic> data) {
    if (data['serverCalculated'] != true) {
      throw const FormatException('The order review is not server-calculated.');
    }
    return OrderReviewPayload(
      orderId: _string(data['orderId'], 'orderId'),
      userId: _string(data['userId'], 'userId'),
      status: _string(data['status'], 'status'),
      serverCalculated: true,
      currency: _string(data['currency'], 'currency'),
      shippingAddressSnapshot: _map(
        data['shippingAddressSnapshot'],
        'shippingAddressSnapshot',
      ),
      deliveryOptionSnapshot: _map(
        data['deliveryOptionSnapshot'],
        'deliveryOptionSnapshot',
      ),
      payment: _map(data['payment'], 'payment'),
      items: _maps(
        data['items'],
        'items',
      ).map(OrderReviewLineItem.fromMap).toList(growable: false),
      pricing: _map(data['pricing'], 'pricing'),
      createdAt: _date(data['createdAt'], 'createdAt'),
      expiresAt: _date(data['expiresAt'], 'expiresAt'),
      acknowledgement: _string(data['acknowledgement'], 'acknowledgement'),
    );
  }

  final String orderId;
  final String userId;
  final String status;
  final bool serverCalculated;
  final String currency;
  final Map<String, dynamic> shippingAddressSnapshot;
  final Map<String, dynamic> deliveryOptionSnapshot;
  final Map<String, dynamic> payment;
  final List<OrderReviewLineItem> items;
  final Map<String, dynamic> pricing;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String acknowledgement;
}

class OrderReviewLineItem {
  const OrderReviewLineItem({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.unitPriceCentavos,
    required this.quantity,
    required this.lineTotalCentavos,
    this.imageUrl,
  });

  factory OrderReviewLineItem.fromMap(Map<String, dynamic> data) {
    return OrderReviewLineItem(
      productId: _string(data['productId'], 'item.productId'),
      variantId: _string(data['variantId'], 'item.variantId'),
      productName: _string(data['productName'], 'item.productName'),
      variantLabel: _string(data['variantLabel'], 'item.variantLabel'),
      unitPriceCentavos: _int(
        data['unitPriceCentavos'],
        'item.unitPriceCentavos',
      ),
      quantity: _int(data['quantity'], 'item.quantity'),
      lineTotalCentavos: _int(
        data['lineTotalCentavos'],
        'item.lineTotalCentavos',
      ),
      imageUrl: data['imageUrl'] is String ? data['imageUrl'] as String : null,
    );
  }

  final String productId;
  final String variantId;
  final String productName;
  final String variantLabel;
  final int unitPriceCentavos;
  final int quantity;
  final int lineTotalCentavos;
  final String? imageUrl;
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map) throw FormatException('Expected $field to be a map.');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Map<String, dynamic>> _maps(Object? value, String field) {
  if (value is! List) throw FormatException('Expected $field to be a list.');
  return value
      .whereType<Map>()
      .map(
        (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
      )
      .toList(growable: false);
}

String _string(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected $field to be a non-empty string.');
}

int _int(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('Expected $field to be an integer.');
}

DateTime _date(Object? value, String field) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Expected $field to be an ISO timestamp.');
}
