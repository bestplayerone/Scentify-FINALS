import 'package:test/test.dart';
import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/inventory/inventory_service.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/cart/data/in_memory_cart_repository.dart';
import 'package:scentify/features/cart/domain/services/cart_service.dart';
import 'package:scentify/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/checkout/data/sandbox_payment_gateway.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/checkout/domain/services/checkout_service.dart';
import 'package:scentify/features/checkout/domain/services/payment_gateway.dart';
import 'package:scentify/features/orders/data/in_memory_order_repository.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

void main() {
  late InMemoryCatalogRepository catalog;
  late InMemoryCartRepository carts;
  late InMemoryOrderRepository orders;
  late Perfume perfume;
  late ShippingAddress address;
  late DeliveryOption delivery;

  setUp(() async {
    perfume = Perfume(
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
    catalog = InMemoryCatalogRepository([perfume]);
    carts = InMemoryCartRepository();
    orders = InMemoryOrderRepository();
    address = ShippingAddress(
      fullName: 'Juan Dela Cruz',
      phoneNumber: '09171234567',
      addressLine1: '123 Mabini Street',
      barangay: 'Barangay 1',
      city: 'Quezon City',
      province: 'Metro Manila',
      postalCode: '1100',
    );
    delivery = DeliveryOption(
      id: 'standard',
      name: 'Standard Delivery',
      fee: Money(1_000_00),
      estimatedDays: '3-5 business days',
    );
  });

  test(
    'checkout reprices from catalog and stores an immutable order snapshot',
    () async {
      final cartService = CartService(
        cartRepository: carts,
        catalogRepository: catalog,
        clock: () => DateTime.utc(2026, 1, 1),
      );
      await cartService.addItem(
        userId: 'customer-1',
        productId: perfume.id,
        variantId: 'scent-50',
        quantity: 2,
      );

      await catalog.save(
        perfume.copyWith(
          variants: [
            perfume.variantById('scent-50')!.copyWith(price: Money(4_000_00)),
          ],
        ),
      );

      final service = CheckoutService(
        cartRepository: carts,
        catalogRepository: catalog,
        inventoryService: InventoryService(catalog),
        orderRepository: orders,
        paymentGateway: SandboxPaymentGateway(),
        clock: () => DateTime.utc(2026, 1, 2),
        idGenerator: () => 'order-1',
      );

      final order = await service.placeOrder(
        userId: 'customer-1',
        shippingAddress: address,
        deliveryOption: delivery,
      );

      expect(order.status, OrderStatus.pendingPayment);
      expect(order.items.single.unitPrice, Money(4_000_00));
      expect(order.subtotal, Money(8_000_00));
      expect(order.total, Money(9_000_00));
      expect(order.paymentReference, startsWith('sandbox-'));
      expect((await carts.findByUserId('customer-1'))?.items, isNull);
      expect(
        (await catalog.findById(perfume.id))!.variantById('scent-50')!.stock,
        2,
      );
    },
  );

  test('payment failure releases the reserved stock', () async {
    final cartService = CartService(
      cartRepository: carts,
      catalogRepository: catalog,
      clock: () => DateTime.utc(2026, 1, 1),
    );
    await cartService.addItem(
      userId: 'customer-1',
      productId: perfume.id,
      variantId: 'scent-50',
    );

    final service = CheckoutService(
      cartRepository: carts,
      catalogRepository: catalog,
      inventoryService: InventoryService(catalog),
      orderRepository: orders,
      paymentGateway: SandboxPaymentGateway(shouldFail: true),
      clock: () => DateTime.utc(2026, 1, 2),
      idGenerator: () => 'order-failed',
    );

    await expectLater(
      service.placeOrder(
        userId: 'customer-1',
        shippingAddress: address,
        deliveryOption: delivery,
      ),
      throwsA(isA<PaymentException>()),
    );
    expect(
      (await catalog.findById(perfume.id))!.variantById('scent-50')!.stock,
      4,
    );
    expect(await orders.findById('order-failed'), isNull);
  });

  test('COD creates a pending confirmation request and reserves stock', () async {
    await CartService(
      cartRepository: carts,
      catalogRepository: catalog,
    ).addItem(
      userId: 'customer-1',
      productId: perfume.id,
      variantId: 'scent-50',
    );
    final gateway = _CountingPaymentGateway();
    final service = CheckoutService(
      cartRepository: carts,
      catalogRepository: catalog,
      inventoryService: InventoryService(catalog),
      orderRepository: orders,
      paymentGateway: gateway,
      idGenerator: () => 'order-cod-unconfigured',
    );

    final order = await service.placeOrder(
      userId: 'customer-1',
      shippingAddress: address,
      deliveryOption: delivery,
      paymentMethod: 'cod',
    );

    expect(gateway.calls, 0);
    expect(order.status.wireValue, 'pending_confirmation');
    expect(order.paymentMethod, 'cod');
    expect(order.paymentStatus, 'unpaid');
    expect(await orders.findById('order-cod-unconfigured'), same(order));
    expect((await carts.findByUserId('customer-1'))?.items, isNull);
    expect(
      (await catalog.findById(perfume.id))!.variantById('scent-50')!.stock,
      3,
    );
  });

  test('checkout consumes only the selected cart items', () async {
    final secondPerfume = perfume.copyWith(
      id: 'scent-2',
      name: 'Second Test Scent',
      variants: [perfume.variants.single.copyWith(id: 'scent-2-50')],
    );
    await catalog.save(secondPerfume);
    final cartService = CartService(
      cartRepository: carts,
      catalogRepository: catalog,
      clock: () => DateTime.utc(2026, 1, 1),
    );
    await cartService.addItem(
      userId: 'customer-1',
      productId: perfume.id,
      variantId: perfume.variants.single.id,
    );
    await cartService.addItem(
      userId: 'customer-1',
      productId: secondPerfume.id,
      variantId: secondPerfume.variants.single.id,
    );
    final selected = (await carts.findByUserId('customer-1'))!.items.first;
    final service = CheckoutService(
      cartRepository: carts,
      catalogRepository: catalog,
      inventoryService: InventoryService(catalog),
      orderRepository: orders,
      paymentGateway: SandboxPaymentGateway(),
      clock: () => DateTime.utc(2026, 1, 2),
      idGenerator: () => 'order-selected',
    );

    final order = await service.placeOrder(
      userId: 'customer-1',
      selectedItems: [selected],
      shippingAddress: address,
      deliveryOption: delivery,
    );

    expect(order.items.single.productId, perfume.id);
    expect(
      (await carts.findByUserId('customer-1'))!.items.single.productId,
      secondPerfume.id,
    );
  });
}

class _CountingPaymentGateway implements PaymentGateway {
  var calls = 0;

  @override
  Future<PaymentSession> createPayment(PaymentRequest request) async {
    calls++;
    return PaymentSession(provider: 'test', reference: 'test-reference');
  }
}
