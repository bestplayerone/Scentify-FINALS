import 'package:test/test.dart';
import 'package:scentify/core/inventory/inventory_service.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/cart/data/in_memory_cart_repository.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/cart/domain/services/cart_service.dart';
import 'package:scentify/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/checkout/domain/models/checkout_quote.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/checkout/domain/services/checkout_service.dart';
import 'package:scentify/features/checkout/domain/services/checkout_review_provider.dart';
import 'package:scentify/features/checkout/domain/services/payment_gateway.dart';
import 'package:scentify/features/orders/data/in_memory_order_repository.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

void main() {
  test('checkout uses the server-reviewed order id and pricing', () async {
    final perfume = Perfume(
      id: 'perfume-1',
      brandId: 'brand-1',
      brandName: 'Test House',
      name: 'Test Scent',
      description: 'A test scent.',
      gender: GenderPreference.unisex,
      family: FragranceFamily.fresh,
      concentration: Concentration.edp,
      occasions: const [Occasion.everyday],
      vibes: const [ScentVibe.clean],
      topNotes: const ['Bergamot'],
      heartNotes: const ['Iris'],
      baseNotes: const ['Musk'],
      variants: [
        PerfumeVariant(
          id: 'perfume-1-50',
          label: '50ml',
          volumeMl: 50,
          price: Money(35_000),
          stock: 5,
        ),
      ],
    );
    final catalog = InMemoryCatalogRepository([perfume]);
    final carts = InMemoryCartRepository();
    final orders = InMemoryOrderRepository();
    await CartService(
      cartRepository: carts,
      catalogRepository: catalog,
    ).addItem(
      userId: 'customer-1',
      productId: perfume.id,
      variantId: 'perfume-1-50',
      quantity: 1,
    );
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
    final reviewProvider = _RecordingReviewProvider(
      CheckoutQuote(
        orderId: 'client-order-1',
        userId: 'customer-1',
        items: [
          CheckoutQuoteItem(
            productId: perfume.id,
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
        total: Money(50_000),
      ),
    );
    final paymentGateway = _RecordingPaymentGateway();
    final service = CheckoutService(
      cartRepository: carts,
      catalogRepository: catalog,
      inventoryService: const NoOpInventoryService(),
      orderRepository: orders,
      paymentGateway: paymentGateway,
      checkoutReviewProvider: reviewProvider,
      idGenerator: () => 'client-order-1',
      clock: () => DateTime.utc(2026, 1, 2),
    );

    final order = await service.placeOrder(
      userId: 'customer-1',
      shippingAddress: address,
      deliveryOption: delivery,
    );

    expect(reviewProvider.requestedOrderId, 'client-order-1');
    expect(reviewProvider.requestedUserId, 'customer-1');
    expect(reviewProvider.requestedItems.single.productId, perfume.id);
    expect(paymentGateway.request?.orderId, 'client-order-1');
    expect(paymentGateway.request?.amount, Money(50_000));
    expect(order.id, 'client-order-1');
    expect(order.items.single.unitPrice, Money(42_000));
    expect(order.subtotal, Money(42_000));
    expect(order.deliveryFee, Money(8_000));
    expect(order.total, Money(50_000));
    expect((await orders.forUser('customer-1')).single.id, 'client-order-1');
    expect(await carts.findByUserId('customer-1'), isNull);
  });

  test(
    'COD delegates final order creation and never starts an online payment',
    () async {
      final perfume = Perfume(
        id: 'cod-perfume',
        brandId: 'brand-1',
        brandName: 'Test House',
        name: 'Test Scent',
        description: 'A test scent.',
        gender: GenderPreference.unisex,
        family: FragranceFamily.fresh,
        concentration: Concentration.edp,
        occasions: const [Occasion.everyday],
        vibes: const [ScentVibe.clean],
        topNotes: const ['Bergamot'],
        heartNotes: const ['Iris'],
        baseNotes: const ['Musk'],
        variants: [
          PerfumeVariant(
            id: 'cod-variant',
            label: '50ml',
            volumeMl: 50,
            price: Money(42_000),
            stock: 5,
          ),
        ],
      );
      final catalog = InMemoryCatalogRepository([perfume]);
      final carts = InMemoryCartRepository();
      final orders = InMemoryOrderRepository();
      await CartService(
        cartRepository: carts,
        catalogRepository: catalog,
      ).addItem(
        userId: 'customer-cod',
        productId: perfume.id,
        variantId: 'cod-variant',
      );
      final address = ShippingAddress(
        fullName: 'Juan Dela Cruz',
        phoneNumber: '09171234567',
        addressLine1: '132 Mabini Street',
        barangay: 'Barangay 132',
        city: 'Caloocan City',
        province: 'National Capital Region',
        postalCode: '1400',
      );
      final delivery = DeliveryOption(
        id: 'standard',
        name: 'Standard Delivery',
        fee: Money(8_000),
        estimatedDays: '3-5 business days',
      );
      final reviewProvider = _RecordingReviewProvider(
        CheckoutQuote(
          orderId: 'cod-order-1',
          userId: 'customer-cod',
          items: [
            CheckoutQuoteItem(
              productId: perfume.id,
              variantId: 'cod-variant',
              productName: perfume.name,
              variantLabel: '50ml',
              unitPrice: Money(42_000),
              quantity: 1,
            ),
          ],
          shippingAddress: address,
          deliveryOption: delivery,
          subtotal: Money(42_000),
          total: Money(50_000),
        ),
      );
      final paymentGateway = _RecordingPaymentGateway();
      final codProvider = _RecordingCodOrderProvider(
        Order(
          id: 'cod-order-1',
          userId: 'customer-cod',
          items: [
            OrderItemSnapshot(
              productId: perfume.id,
              variantId: 'cod-variant',
              productName: perfume.name,
              variantLabel: '50ml',
              unitPrice: Money(42_000),
              quantity: 1,
            ),
          ],
          shippingAddress: address,
          deliveryOption: delivery,
          subtotal: Money(42_000),
          deliveryFee: Money(8_000),
          total: Money(50_000),
          status: OrderStatus.confirmed,
          paymentMethod: 'cod',
          paymentStatus: 'pending_collection',
          createdAt: DateTime.utc(2026, 1, 2),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      final service = CheckoutService(
        cartRepository: carts,
        catalogRepository: catalog,
        inventoryService: const NoOpInventoryService(),
        orderRepository: orders,
        paymentGateway: paymentGateway,
        checkoutReviewProvider: reviewProvider,
        cashOnDeliveryOrderProvider: codProvider,
        clock: () => DateTime.utc(2026, 1, 2),
      );

      final order = await service.placeOrder(
        userId: 'customer-cod',
        orderId: 'cod-order-1',
        shippingAddress: address,
        deliveryOption: delivery,
        paymentMethod: 'cod',
      );

      expect(reviewProvider.requestedOrderId, 'cod-order-1');
      expect(codProvider.requestedOrderId, 'cod-order-1');
      expect(paymentGateway.request, isNull);
      expect(order.paymentMethod, 'cod');
      expect(order.paymentStatus, 'pending_collection');
      expect(await orders.findById('cod-order-1'), isNull);
      expect((await carts.findByUserId('customer-cod'))?.items.length, 1);
    },
  );
}

class _RecordingReviewProvider implements CheckoutReviewProvider {
  _RecordingReviewProvider(this.payload);

  final CheckoutQuote payload;
  String? requestedOrderId;
  String? requestedUserId;
  List<CartItem> requestedItems = const [];

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
    requestedOrderId = orderId;
    requestedUserId = userId;
    requestedItems = selectedItems;
    return payload;
  }
}

class _RecordingPaymentGateway implements PaymentGateway {
  PaymentRequest? request;

  @override
  Future<PaymentSession> createPayment(PaymentRequest request) async {
    this.request = request;
    return PaymentSession(
      provider: 'test',
      reference: 'sandbox-gcash-${request.orderId}-1',
    );
  }
}

class _RecordingCodOrderProvider implements CashOnDeliveryOrderProvider {
  _RecordingCodOrderProvider(this.order);

  final Order order;
  String? requestedOrderId;

  @override
  Future<Order> createCashOnDeliveryOrder({
    required String orderId,
    required String userId,
    required ShippingAddress shippingAddress,
    required DeliveryOption deliveryOption,
  }) async {
    requestedOrderId = orderId;
    return order;
  }
}
