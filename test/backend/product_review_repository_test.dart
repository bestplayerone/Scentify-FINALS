import 'dart:async';

import 'package:test/test.dart';
import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/catalog/data/in_memory_product_review_repository.dart';

void main() {
  final address = ShippingAddress(
    fullName: 'Juan Dela Cruz',
    phoneNumber: '09171234567',
    addressLine1: '123 Mabini Street',
    barangay: 'Barangay 1',
    city: 'Quezon City',
    province: 'Metro Manila',
    postalCode: '1100',
  );
  final delivery = DeliveryOption(
    id: 'standard',
    name: 'Standard Delivery',
    fee: Money(8_000),
    estimatedDays: '3-5 business days',
  );

  Order orderWithStatus(OrderStatus status) => Order(
    id: 'order-1',
    userId: 'customer-1',
    items: [
      OrderItemSnapshot(
        productId: 'perfume-1',
        variantId: 'perfume-1-50',
        productName: 'Test Scent',
        variantLabel: '50ml',
        unitPrice: Money(42_000),
        quantity: 1,
      ),
    ],
    shippingAddress: address,
    deliveryOption: delivery,
    subtotal: Money(42_000),
    deliveryFee: delivery.fee,
    total: Money(50_000),
    status: status,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  test('only delivered order items can receive one verified rating', () async {
    final repository = InMemoryProductReviewRepository();
    final iterator = StreamIterator(repository.watchForProduct('perfume-1'));

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isEmpty);
    await expectLater(
      repository.submit(
        order: orderWithStatus(OrderStatus.shipped),
        item: orderWithStatus(OrderStatus.shipped).items.single,
        rating: 5,
      ),
      throwsA(isA<ValidationException>()),
    );

    final delivered = orderWithStatus(OrderStatus.delivered);
    final review = await repository.submit(
      order: delivered,
      item: delivered.items.single,
      rating: 5,
      title: 'Lovely scent',
      comment: 'Lasts all day.',
    );
    expect(review.verifiedPurchase, isTrue);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, hasLength(1));
    expect(iterator.current.single.title, 'Lovely scent');
    expect(
      await repository.hasReviewForOrderItem(
        orderId: delivered.id,
        productId: 'perfume-1',
        variantId: 'perfume-1-50',
      ),
      isTrue,
    );
    await expectLater(
      repository.submit(
        order: delivered,
        item: delivered.items.single,
        rating: 4,
      ),
      throwsA(isA<ConflictException>()),
    );
    await iterator.cancel();
  });
}
