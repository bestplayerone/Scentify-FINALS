import 'package:test/test.dart';
import 'package:scentify/core/firebase/firestore_codecs.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

void main() {
  test('perfume codec preserves catalog data and centavo prices', () {
    final perfume = Perfume(
      id: 'scent-1',
      brandId: 'brand-1',
      brandName: 'Maison Test',
      name: 'Test Scent',
      description: 'Test perfume',
      gender: GenderPreference.unisex,
      family: FragranceFamily.fresh,
      concentration: Concentration.edp,
      occasions: [Occasion.everyday, Occasion.office],
      vibes: [ScentVibe.clean, ScentVibe.calming],
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
      imageUrls: ['https://example.com/scent.png'],
      tags: ['clean'],
      authenticityNote: 'Authentic.',
      isPublished: true,
    );

    final restored = FirestoreCodecs.perfumeFromMap(
      perfume.id,
      FirestoreCodecs.perfumeToMap(perfume),
    );

    expect(restored.id, perfume.id);
    expect(restored.family, perfume.family);
    expect(restored.occasions, perfume.occasions);
    expect(restored.vibes, perfume.vibes);
    expect(restored.variants.single.price, Money(3_500_00));
    expect(restored.variants.single.stock, 4);
  });

  test('cart codec preserves user ownership and updated time', () {
    final cart = Cart(
      userId: 'customer-1',
      updatedAt: DateTime.utc(2026, 1, 2),
      items: [
        CartItem(
          productId: 'scent-1',
          variantId: 'scent-50',
          productName: 'Test Scent',
          variantLabel: '50ml',
          unitPrice: Money(3_500_00),
          quantity: 2,
        ),
      ],
    );

    final restored = FirestoreCodecs.cartFromMap(
      FirestoreCodecs.cartToMap(cart),
    );

    expect(restored.userId, cart.userId);
    expect(restored.updatedAt, cart.updatedAt);
    expect(restored.items.single.lineTotal, Money(7_000_00));
  });

  test('order codec preserves nested address and status events', () {
    final order = Order(
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
      shippingAddress: ShippingAddress(
        fullName: 'Juan Dela Cruz',
        phoneNumber: '09171234567',
        addressLine1: '123 Mabini Street',
        barangay: 'Barangay 1',
        city: 'Quezon City',
        province: 'Metro Manila',
        postalCode: '1100',
      ),
      deliveryOption: DeliveryOption(
        id: 'standard',
        name: 'Standard Delivery',
        fee: Money(1_000_00),
        estimatedDays: '3-5 business days',
      ),
      subtotal: Money(3_500_00),
      deliveryFee: Money(1_000_00),
      total: Money(4_500_00),
      status: OrderStatus.confirmed,
      paymentReference: 'payment-1',
      paymentMethod: 'cod',
      paymentStatus: 'pending_collection',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      events: [
        OrderStatusEvent(
          from: OrderStatus.pendingPayment,
          to: OrderStatus.confirmed,
          changedAt: DateTime.utc(2026, 1, 2),
          actorId: 'admin-1',
        ),
      ],
    );

    final restored = FirestoreCodecs.orderFromMap(
      FirestoreCodecs.orderToMap(order),
    );

    expect(restored.id, order.id);
    expect(restored.shippingAddress.city, 'Quezon City');
    expect(restored.deliveryOption.fee, Money(1_000_00));
    expect(restored.status, OrderStatus.confirmed);
    expect(restored.paymentMethod, 'cod');
    expect(restored.paymentStatus, 'pending_collection');
    expect(restored.events.single.actorId, 'admin-1');
  });
}
