import 'dart:async';

import 'package:test/test.dart';
import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/admin/domain/services/admin_catalog_service.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/orders/data/in_memory_order_repository.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/orders/domain/services/admin_order_service.dart';
import 'package:scentify/features/orders/domain/services/order_service.dart';
import 'package:scentify/features/orders/domain/services/order_status_machine.dart';

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
    fee: Money(1_000_00),
    estimatedDays: '3-5 business days',
  );
  final baseOrder = Order(
    id: 'order-1',
    userId: 'customer-1',
    items: [
      OrderItemSnapshot(
        productId: 'scent-1',
        variantId: 'scent-50',
        productName: 'Test Scent',
        variantLabel: '50ml',
        unitPrice: Money(3_500_00),
        quantity: 1,
      ),
    ],
    shippingAddress: address,
    deliveryOption: delivery,
    subtotal: Money(3_500_00),
    deliveryFee: Money(1_000_00),
    total: Money(4_500_00),
    status: OrderStatus.pendingPayment,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  test('allows only the exact forward order status sequence', () {
    final machine = OrderStatusMachine();
    var current = OrderStatus.pendingPayment;
    const sequence = [
      OrderStatus.confirmed,
      OrderStatus.processing,
      OrderStatus.packed,
      OrderStatus.shipped,
      OrderStatus.delivered,
    ];

    for (final next in sequence) {
      expect(machine.canTransition(current, next), isTrue);
      current = next;
    }

    expect(
      () => machine.assertTransition(
        OrderStatus.pendingPayment,
        OrderStatus.shipped,
      ),
      throwsA(isA<InvalidOrderTransitionException>()),
    );
  });

  test(
    'order service records a status event with the actor and time',
    () async {
      final repository = InMemoryOrderRepository();
      await repository.save(baseOrder);
      final service = OrderService(
        repository,
        clock: () => DateTime.utc(2026, 1, 2),
      );

      final updated = await service.transitionStatus(
        orderId: baseOrder.id,
        nextStatus: OrderStatus.confirmed,
        actorId: 'admin-1',
      );

      expect(updated.status, OrderStatus.confirmed);
      expect(updated.events, hasLength(1));
      expect(updated.events.single.from, OrderStatus.pendingPayment);
      expect(updated.events.single.to, OrderStatus.confirmed);
      expect(updated.events.single.actorId, 'admin-1');
    },
  );

  test(
    'order repository streams new orders for the current customer',
    () async {
      final repository = InMemoryOrderRepository();
      final orders = StreamIterator(repository.watchForUser('customer-1'));

      expect(await orders.moveNext(), isTrue);
      expect(orders.current, isEmpty);

      await repository.save(baseOrder);
      expect(await orders.moveNext(), isTrue);
      expect(orders.current.single.id, baseOrder.id);
      await orders.cancel();
    },
  );

  test('admin order service rejects customer status changes', () async {
    final repository = InMemoryOrderRepository();
    await repository.save(baseOrder);
    final service = AdminOrderService(repository);
    final customer = UserProfile(
      id: 'customer-1',
      email: 'customer@example.com',
      displayName: 'Customer',
      role: UserRole.customer,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    expect(
      () => service.transitionStatus(
        actor: customer,
        orderId: baseOrder.id,
        nextStatus: OrderStatus.confirmed,
      ),
      throwsA(isA<AuthorizationException>()),
    );
    expect((await repository.findById(baseOrder.id))?.status,
        OrderStatus.pendingPayment);
  });

  test('admin order service approves a pending payment', () async {
    final repository = InMemoryOrderRepository();
    await repository.save(baseOrder);
    final service = AdminOrderService(
      repository,
      clock: () => DateTime.utc(2026, 1, 2),
    );
    final admin = UserProfile(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Scentify Admin',
      role: UserRole.admin,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    final updated = await service.transitionStatus(
      actor: admin,
      orderId: baseOrder.id,
      nextStatus: OrderStatus.confirmed,
    );

    expect(updated.status, OrderStatus.confirmed);
    expect(updated.events.single.actorId, admin.id);
  });

  test('only admins can write products through the admin service', () async {
    final catalog = InMemoryCatalogRepository();
    final service = AdminCatalogService(catalog);
    final customer = UserProfile(
      id: 'customer-1',
      email: 'customer@example.com',
      displayName: 'Customer',
      role: UserRole.customer,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final admin = customer.copyWith(role: UserRole.admin);

    final product = Perfume(
      id: 'scent-1',
      brandId: 'brand-1',
      brandName: 'Maison Test',
      name: 'Test Scent',
      description: 'Test perfume',
      gender: GenderPreference.unisex,
      family: FragranceFamily.fresh,
      concentration: Concentration.edp,
      occasions: [Occasion.everyday],
      vibes: [ScentVibe.clean],
      topNotes: ['Bergamot'],
      heartNotes: ['Iris'],
      baseNotes: ['Musk'],
      variants: [
        PerfumeVariant(
          id: 'scent-50',
          label: '50ml',
          volumeMl: 50,
          price: Money(3_500_00),
          stock: 4,
        ),
      ],
    );

    expect(
      () => service.saveProduct(actor: customer, product: product),
      throwsA(isA<AuthorizationException>()),
    );
    await service.saveProduct(actor: admin, product: product);
    expect(await catalog.findById(product.id), isNotNull);
    await service.deleteProduct(actor: admin, productId: product.id);
    expect(await catalog.findById(product.id), isNull);
  });
}
