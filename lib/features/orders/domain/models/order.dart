import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';

enum OrderStatus {
  pendingPayment,
  pendingConfirmation,
  confirmed,
  processing,
  packed,
  shipped,
  delivered,
  cancelled,
}

extension OrderStatusWireValue on OrderStatus {
  String get wireValue => switch (this) {
    OrderStatus.pendingPayment => 'pending_payment',
    OrderStatus.pendingConfirmation => 'pending_confirmation',
    OrderStatus.confirmed => 'confirmed',
    OrderStatus.processing => 'processing',
    OrderStatus.packed => 'packed',
    OrderStatus.shipped => 'shipped',
    OrderStatus.delivered => 'delivered',
    OrderStatus.cancelled => 'cancelled',
  };
}

class OrderItemSnapshot {
  OrderItemSnapshot({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.unitPrice,
    required this.quantity,
  });

  final String productId;
  final String variantId;
  final String productName;
  final String variantLabel;
  final Money unitPrice;
  final int quantity;

  Money get lineTotal => unitPrice * quantity;
}

class OrderStatusEvent {
  OrderStatusEvent({
    required this.from,
    required this.to,
    required this.changedAt,
    required this.actorId,
  });

  final OrderStatus? from;
  final OrderStatus to;
  final DateTime changedAt;
  final String actorId;
}

class Order {
  Order({
    required this.id,
    required this.userId,
    required List<OrderItemSnapshot> items,
    required this.shippingAddress,
    required this.deliveryOption,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.paymentReference,
    this.paymentMethod,
    this.paymentStatus,
    List<OrderStatusEvent> events = const [],
  }) : items = List.unmodifiable(items),
       events = List.unmodifiable(events);

  final String id;
  final String userId;
  final List<OrderItemSnapshot> items;
  final ShippingAddress shippingAddress;
  final DeliveryOption deliveryOption;
  final Money subtotal;
  final Money deliveryFee;
  final Money total;
  final OrderStatus status;
  final String? paymentReference;
  final String? paymentMethod;
  final String? paymentStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<OrderStatusEvent> events;

  Order copyWith({
    String? id,
    String? userId,
    List<OrderItemSnapshot>? items,
    ShippingAddress? shippingAddress,
    DeliveryOption? deliveryOption,
    Money? subtotal,
    Money? deliveryFee,
    Money? total,
    OrderStatus? status,
    String? paymentReference,
    String? paymentMethod,
    String? paymentStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<OrderStatusEvent>? events,
  }) {
    return Order(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      items: items ?? this.items,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      deliveryOption: deliveryOption ?? this.deliveryOption,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      total: total ?? this.total,
      status: status ?? this.status,
      paymentReference: paymentReference ?? this.paymentReference,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      events: events ?? this.events,
    );
  }
}
