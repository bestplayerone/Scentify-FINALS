import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/catalog/data/in_memory_product_review_repository.dart';

import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/main.dart';

void main() {
  testWidgets('product details display verified reviews from the repository', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = InMemoryProductReviewRepository();
    addTearDown(repository.dispose);
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
    final item = OrderItemSnapshot(
      productId: 'review-product',
      variantId: 'review-variant',
      productName: 'Review Scent',
      variantLabel: '50ml',
      unitPrice: Money(42_000),
      quantity: 1,
    );
    final order = Order(
      id: 'review-order',
      userId: 'customer-1',
      items: [item],
      shippingAddress: address,
      deliveryOption: delivery,
      subtotal: Money(42_000),
      deliveryFee: delivery.fee,
      total: Money(50_000),
      status: OrderStatus.delivered,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    await repository.submit(
      order: order,
      item: item,
      rating: 5,
      title: 'Smells wonderful',
      comment: 'Lasts all day.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProductPage(
          product: const Product(
            id: 'review-product',
            name: 'Review Scent',
            brand: 'Test House',
            price: 420,
            availableVolumes: ['50ml'],
            stockByVolume: {'50ml': 1},
          ),
          isFavorite: false,
          onBack: () {},
          onFavorite: () {},
          onAddToCart: (_, _) {},
          reviewRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product-reviews-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Smells wonderful'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('review-comment-input')))
          .controller!
          .text,
      'Lasts all day.',
    );
    expect(find.text('Verified purchase'), findsOneWidget);
    expect(find.text('5.0 · 1 review'), findsOneWidget);
  });

  testWidgets('delivered purchases can submit a verified product rating', (
    tester,
  ) async {
    final repository = InMemoryProductReviewRepository();
    addTearDown(repository.dispose);
    final item = OrderItemSnapshot(
      productId: 'review-product',
      variantId: 'review-variant',
      productName: 'Review Scent',
      variantLabel: '50ml',
      unitPrice: Money(42_000),
      quantity: 1,
    );
    final order = Order(
      id: 'review-order',
      userId: 'customer-1',
      items: [item],
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
        fee: Money(8_000),
        estimatedDays: '3-5 business days',
      ),
      subtotal: Money(42_000),
      deliveryFee: Money(8_000),
      total: Money(50_000),
      status: OrderStatus.delivered,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

    var submissionAttempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MyPurchasesPage(
            orders: [order],
            products: const [
              Product(
                id: 'review-product',
                name: 'Review Scent',
                brand: 'Test House',
                price: 420,
              ),
            ],
            onBack: () {},
            onOrder: (_) {},
            reviewRepository: repository,
            onSubmitReview: (purchase, purchaseItem, rating, title, comment) {
              if (submissionAttempts++ == 0) {
                throw StateError('temporary network failure');
              }
              return repository.submit(
                order: purchase,
                item: purchaseItem,
                rating: rating,
                title: title,
                comment: comment,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Rate this item'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('review-submit-button')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('review-rating-4')));
    await tester.tap(find.byKey(const Key('review-comment-input')));
    tester.testTextInput.enterText('Lasts all day.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-submit-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text(
        'Your review could not be saved. Your entries are still here; try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Lasts all day.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-submit-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Review submitted'), findsOneWidget);
    expect(find.text('Reviewed'), findsOneWidget);
    expect(
      await repository.hasReviewForOrderItem(
        orderId: order.id,
        productId: item.productId,
        variantId: item.variantId,
      ),
      isTrue,
    );
    final savedReview = repository.latestForProduct(item.productId)!;
    expect(savedReview.title, isEmpty);
    expect(savedReview.comment, 'Lasts all day.');
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    tester.testTextInput.closeConnection();
  });
}
