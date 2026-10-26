import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

class FirestoreCodecs {
  static Map<String, dynamic> perfumeToMap(Perfume perfume) => {
    'brandId': perfume.brandId,
    'brandName': perfume.brandName,
    'name': perfume.name,
    'description': perfume.description,
    'gender': perfume.gender.wireValue,
    'family': perfume.family.wireValue,
    'concentration': perfume.concentration.wireValue,
    'occasions': perfume.occasions.map((value) => value.wireValue).toList(),
    'vibes': perfume.vibes.map((value) => value.wireValue).toList(),
    'topNotes': perfume.topNotes,
    'heartNotes': perfume.heartNotes,
    'baseNotes': perfume.baseNotes,
    'variants': perfume.variants.map(_variantToMap).toList(),
    'imageUrls': perfume.imageUrls,
    'tags': perfume.tags,
    'authenticityNote': perfume.authenticityNote,
    'isPublished': perfume.isPublished,
  };

  static Perfume perfumeFromMap(String id, Map<String, dynamic> data) {
    return Perfume(
      id: id,
      brandId: _string(data['brandId'], 'brandId'),
      brandName: _string(data['brandName'], 'brandName'),
      name: _string(data['name'], 'name'),
      description: _string(data['description'], 'description'),
      gender: _gender(data['gender']),
      family: _family(data['family']),
      concentration: _concentration(data['concentration']),
      occasions: _list(data['occasions'], 'occasions').map(_occasion).toList(),
      vibes: _list(data['vibes'], 'vibes').map(_vibe).toList(),
      topNotes: _strings(data['topNotes'], 'topNotes'),
      heartNotes: _strings(data['heartNotes'], 'heartNotes'),
      baseNotes: _strings(data['baseNotes'], 'baseNotes'),
      variants: _list(
        data['variants'],
        'variants',
      ).map((value) => _variantFromMap(_map(value, 'variant'))).toList(),
      imageUrls: _strings(data['imageUrls'], 'imageUrls'),
      tags: _strings(data['tags'], 'tags'),
      authenticityNote: _string(data['authenticityNote'], 'authenticityNote'),
      isPublished: _bool(data['isPublished'], 'isPublished'),
    );
  }

  static Map<String, dynamic> cartToMap(Cart cart) => {
    'userId': cart.userId,
    'updatedAt': cart.updatedAt,
    'items': cart.items.map(_cartItemToMap).toList(),
  };

  static Cart cartFromMap(Map<String, dynamic> data) {
    return Cart(
      userId: _string(data['userId'], 'userId'),
      updatedAt: _date(data['updatedAt'], 'updatedAt'),
      items: _list(
        data['items'],
        'items',
      ).map((value) => _cartItemFromMap(_map(value, 'cart item'))).toList(),
    );
  }

  static Map<String, dynamic> orderToMap(Order order) => {
    'id': order.id,
    'userId': order.userId,
    'items': order.items.map(_orderItemToMap).toList(),
    'shippingAddress': _addressToMap(order.shippingAddress),
    'deliveryOption': _deliveryToMap(order.deliveryOption),
    'subtotalCentavos': order.subtotal.centavos,
    'deliveryFeeCentavos': order.deliveryFee.centavos,
    'totalCentavos': order.total.centavos,
    'status': order.status.wireValue,
    'paymentReference': order.paymentReference,
    if (order.paymentMethod != null) 'paymentMethod': order.paymentMethod,
    if (order.paymentStatus != null) 'paymentStatus': order.paymentStatus,
    'createdAt': order.createdAt,
    'updatedAt': order.updatedAt,
    'events': order.events.map(_eventToMap).toList(),
  };

  static Order orderFromMap(Map<String, dynamic> data, {String? id}) {
    return Order(
      id: id ?? _string(data['id'], 'id'),
      userId: _string(data['userId'], 'userId'),
      items: _list(
        data['items'],
        'items',
      ).map((value) => _orderItemFromMap(_map(value, 'order item'))).toList(),
      shippingAddress: _addressFromMap(
        _map(data['shippingAddress'], 'shippingAddress'),
      ),
      deliveryOption: _deliveryFromMap(
        _map(data['deliveryOption'], 'deliveryOption'),
      ),
      subtotal: Money(_int(data['subtotalCentavos'], 'subtotalCentavos')),
      deliveryFee: Money(
        _int(data['deliveryFeeCentavos'], 'deliveryFeeCentavos'),
      ),
      total: Money(_int(data['totalCentavos'], 'totalCentavos')),
      status: _status(data['status']),
      paymentReference: _nullableString(data['paymentReference']),
      paymentMethod: _nullableString(data['paymentMethod']),
      paymentStatus: _nullableString(data['paymentStatus']),
      createdAt: _date(data['createdAt'], 'createdAt'),
      updatedAt: _date(data['updatedAt'], 'updatedAt'),
      events: _list(
        data['events'],
        'events',
      ).map((value) => _eventFromMap(_map(value, 'status event'))).toList(),
    );
  }

  static Map<String, dynamic> _variantToMap(PerfumeVariant variant) => {
    'id': variant.id,
    'label': variant.label,
    'volumeMl': variant.volumeMl,
    'priceCentavos': variant.price.centavos,
    'stock': variant.stock,
  };

  static PerfumeVariant _variantFromMap(Map<String, dynamic> data) {
    return PerfumeVariant(
      id: _string(data['id'], 'variant.id'),
      label: _string(data['label'], 'variant.label'),
      volumeMl: _int(data['volumeMl'], 'variant.volumeMl'),
      price: Money(_int(data['priceCentavos'], 'variant.priceCentavos')),
      stock: _int(data['stock'], 'variant.stock'),
    );
  }

  static Map<String, dynamic> _cartItemToMap(CartItem item) => {
    'productId': item.productId,
    'variantId': item.variantId,
    'productName': item.productName,
    'variantLabel': item.variantLabel,
    'unitPriceCentavos': item.unitPrice.centavos,
    'quantity': item.quantity,
  };

  static CartItem _cartItemFromMap(Map<String, dynamic> data) {
    return CartItem(
      productId: _string(data['productId'], 'cartItem.productId'),
      variantId: _string(data['variantId'], 'cartItem.variantId'),
      productName: _string(data['productName'], 'cartItem.productName'),
      variantLabel: _string(data['variantLabel'], 'cartItem.variantLabel'),
      unitPrice: Money(
        _int(data['unitPriceCentavos'], 'cartItem.unitPriceCentavos'),
      ),
      quantity: _int(data['quantity'], 'cartItem.quantity'),
    );
  }

  static Map<String, dynamic> _orderItemToMap(OrderItemSnapshot item) => {
    'productId': item.productId,
    'variantId': item.variantId,
    'productName': item.productName,
    'variantLabel': item.variantLabel,
    'unitPriceCentavos': item.unitPrice.centavos,
    'quantity': item.quantity,
  };

  static OrderItemSnapshot _orderItemFromMap(Map<String, dynamic> data) {
    return OrderItemSnapshot(
      productId: _string(data['productId'], 'orderItem.productId'),
      variantId: _string(data['variantId'], 'orderItem.variantId'),
      productName: _string(data['productName'], 'orderItem.productName'),
      variantLabel: _string(data['variantLabel'], 'orderItem.variantLabel'),
      unitPrice: Money(
        _int(data['unitPriceCentavos'], 'orderItem.unitPriceCentavos'),
      ),
      quantity: _int(data['quantity'], 'orderItem.quantity'),
    );
  }

  static Map<String, dynamic> _addressToMap(ShippingAddress address) => {
    'fullName': address.fullName,
    'phoneNumber': address.phoneNumber,
    'addressLine1': address.addressLine1,
    'barangay': address.barangay,
    'city': address.city,
    'province': address.province,
    'postalCode': address.postalCode,
    'notes': address.notes,
  };

  static ShippingAddress _addressFromMap(Map<String, dynamic> data) {
    return ShippingAddress(
      fullName: _string(data['fullName'], 'shippingAddress.fullName'),
      phoneNumber: _string(data['phoneNumber'], 'shippingAddress.phoneNumber'),
      addressLine1: _string(
        data['addressLine1'],
        'shippingAddress.addressLine1',
      ),
      barangay: _string(data['barangay'], 'shippingAddress.barangay'),
      city: _string(data['city'], 'shippingAddress.city'),
      province: _string(data['province'], 'shippingAddress.province'),
      postalCode: _string(data['postalCode'], 'shippingAddress.postalCode'),
      notes: _string(data['notes'], 'shippingAddress.notes'),
    );
  }

  static Map<String, dynamic> _deliveryToMap(DeliveryOption delivery) => {
    'id': delivery.id,
    'name': delivery.name,
    'feeCentavos': delivery.fee.centavos,
    'estimatedDays': delivery.estimatedDays,
  };

  static DeliveryOption _deliveryFromMap(Map<String, dynamic> data) {
    return DeliveryOption(
      id: _string(data['id'], 'deliveryOption.id'),
      name: _string(data['name'], 'deliveryOption.name'),
      fee: Money(_int(data['feeCentavos'], 'deliveryOption.feeCentavos')),
      estimatedDays: _string(
        data['estimatedDays'],
        'deliveryOption.estimatedDays',
      ),
    );
  }

  static Map<String, dynamic> _eventToMap(OrderStatusEvent event) => {
    'from': event.from?.wireValue,
    'to': event.to.wireValue,
    'changedAt': event.changedAt,
    'actorId': event.actorId,
  };

  static OrderStatusEvent _eventFromMap(Map<String, dynamic> data) {
    return OrderStatusEvent(
      from: _nullableStatus(data['from']),
      to: _status(data['to']),
      changedAt: _date(data['changedAt'], 'event.changedAt'),
      actorId: _string(data['actorId'], 'event.actorId'),
    );
  }

  static Map<String, dynamic> _map(Object? value, String field) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('Expected $field to be a map.');
  }

  static List<Object?> _list(Object? value, String field) {
    if (value is List) {
      return value.cast<Object?>();
    }
    throw FormatException('Expected $field to be a list.');
  }

  static List<String> _strings(Object? value, String field) {
    return _list(value, field).map((item) => _string(item, field)).toList();
  }

  static String _string(Object? value, String field) {
    if (value is String) {
      return value;
    }
    throw FormatException('Expected $field to be a string.');
  }

  static String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }
    return _string(value, 'nullable string');
  }

  static int _int(Object? value, String field) {
    if (value is int) {
      return value;
    }
    throw FormatException('Expected $field to be an integer.');
  }

  static bool _bool(Object? value, String field) {
    if (value is bool) {
      return value;
    }
    throw FormatException('Expected $field to be a boolean.');
  }

  static DateTime _date(Object? value, String field) {
    if (value is DateTime) {
      return value;
    }
    try {
      final dynamic timestamp = value;
      final date = timestamp.toDate();
      if (date is DateTime) {
        return date;
      }
    } on Object {
      // Firestore Timestamp values expose toDate(); other values are invalid.
    }
    throw FormatException('Expected $field to be a Firestore timestamp.');
  }

  static GenderPreference _gender(Object? value) {
    final wireValue = _string(value, 'gender');
    return GenderPreference.values.firstWhere(
      (item) => item.wireValue == wireValue,
      orElse: () => throw FormatException('Invalid gender: $wireValue.'),
    );
  }

  static FragranceFamily _family(Object? value) {
    return _enumByName(FragranceFamily.values, value, 'family');
  }

  static Concentration _concentration(Object? value) {
    return _enumByName(Concentration.values, value, 'concentration');
  }

  static Occasion _occasion(Object? value) {
    return _enumByName(Occasion.values, value, 'occasion');
  }

  static ScentVibe _vibe(Object? value) {
    return _enumByName(ScentVibe.values, value, 'vibe');
  }

  static OrderStatus _status(Object? value) {
    final wireValue = _string(value, 'status');
    return OrderStatus.values.firstWhere(
      (item) => item.wireValue == wireValue,
      orElse: () => throw FormatException('Invalid status: $wireValue.'),
    );
  }

  static OrderStatus? _nullableStatus(Object? value) {
    if (value == null) {
      return null;
    }
    return _status(value);
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? rawValue,
    String field,
  ) {
    final value = _string(rawValue, field);
    return values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw FormatException('Invalid $field: $value.'),
    );
  }
}
