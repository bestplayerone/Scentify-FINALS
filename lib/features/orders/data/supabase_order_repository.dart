import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/orders/domain/repositories/order_repository.dart';

class SupabaseOrderRepository implements OrderRepository {
  SupabaseOrderRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<void> save(Order order) => throw UnsupportedError('Orders are created by Supabase checkout RPCs.');

  @override
  Future<Order?> findById(String orderId) async {
    final row = await _client.from('orders').select('*, order_items(*)').eq('id', orderId).maybeSingle();
    return row == null ? null : _decode(row);
  }

  @override
  Future<List<Order>> forUser(String userId) async {
    final rows = await _client.from('orders').select('*, order_items(*)').eq('user_id', userId).order('created_at', ascending: false);
    return rows.map<Order>(_decode).toList();
  }

  @override
  Stream<List<Order>> watchForUser(String userId) async* {
    yield await forUser(userId);
    yield* Stream.periodic(const Duration(seconds: 5)).asyncMap((_) => forUser(userId));
  }

  @override
  Stream<List<Order>> watchAll() => const Stream.empty();

  Order _decode(Map<String, dynamic> row) {
    final address = Map<String, dynamic>.from(row['shipping_address'] as Map);
    final delivery = Map<String, dynamic>.from(row['delivery_option'] as Map);
    return Order(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      items: [for (final item in (row['order_items'] as List? ?? const [])) OrderItemSnapshot(productId: item['product_id'] as String, variantId: item['variant_id'] as String, productName: item['product_name'] as String, variantLabel: item['variant_label'] as String, unitPrice: Money((item['unit_price_centavos'] as num).toInt()), quantity: (item['quantity'] as num).toInt())],
      shippingAddress: ShippingAddress(fullName: address['fullName'] as String, phoneNumber: address['phoneNumber'] as String, addressLine1: address['addressLine1'] as String, barangay: address['barangay'] as String, city: address['city'] as String, province: address['province'] as String, postalCode: address['postalCode'] as String, notes: (address['notes'] as String?) ?? ''),
      deliveryOption: DeliveryOption(id: delivery['id'] as String, name: delivery['name'] as String, fee: Money((delivery['feeCentavos'] as num).toInt()), estimatedDays: delivery['estimatedDays'] as String),
      subtotal: Money((row['subtotal_centavos'] as num).toInt()),
      deliveryFee: Money((row['delivery_fee_centavos'] as num).toInt()),
      total: Money((row['total_centavos'] as num).toInt()),
      status: OrderStatus.values.firstWhere((status) => status.wireValue == row['status'], orElse: () => OrderStatus.pendingPayment),
      paymentReference: row['payment_reference'] as String?, paymentMethod: row['payment_method'] as String?, paymentStatus: row['payment_status'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String), updatedAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
