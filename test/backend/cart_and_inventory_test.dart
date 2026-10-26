import 'dart:async';

import 'package:test/test.dart';
import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/inventory/inventory_service.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/cart/data/in_memory_cart_repository.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/cart/domain/services/cart_service.dart';
import 'package:scentify/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';

void main() {
  late InMemoryCatalogRepository catalog;
  late InMemoryCartRepository carts;
  late Perfume perfume;

  setUp(() {
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
          stock: 3,
        ),
      ],
    );
    catalog = InMemoryCatalogRepository([perfume]);
    carts = InMemoryCartRepository();
  });

  test('cart refuses a quantity higher than current variant stock', () async {
    final service = CartService(
      cartRepository: carts,
      catalogRepository: catalog,
      clock: () => DateTime.utc(2026, 1, 1),
    );

    await service.addItem(
      userId: 'customer-1',
      productId: perfume.id,
      variantId: 'scent-50',
      quantity: 2,
    );

    expect(
      () => service.addItem(
        userId: 'customer-1',
        productId: perfume.id,
        variantId: 'scent-50',
        quantity: 2,
      ),
      throwsA(isA<InsufficientStockException>()),
    );
  });

  test('cart stream emits saved and cleared snapshots', () async {
    final iterator = StreamIterator(carts.watch('customer-1'));

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isNull);

    await carts.save(
      Cart(
        userId: 'customer-1',
        updatedAt: DateTime.utc(2026, 1, 1),
        items: [
          CartItem(
            productId: perfume.id,
            variantId: 'scent-50',
            productName: perfume.name,
            variantLabel: '50ml',
            unitPrice: Money(3_500_00),
            quantity: 1,
          ),
        ],
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current?.items.single.productId, perfume.id);

    await carts.clear('customer-1');
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isNull);

    await iterator.cancel();
  });

  test('inventory reservation never leaves a negative stock value', () async {
    final service = InventoryService(catalog);

    await service.reserve([
      InventoryRequest(
        productId: perfume.id,
        variantId: 'scent-50',
        quantity: 2,
      ),
    ]);

    expect(
      (await catalog.findById(perfume.id))!.variantById('scent-50')!.stock,
      1,
    );

    expect(
      () => service.reserve([
        InventoryRequest(
          productId: perfume.id,
          variantId: 'scent-50',
          quantity: 2,
        ),
      ]),
      throwsA(isA<InsufficientStockException>()),
    );
    expect(
      (await catalog.findById(perfume.id))!.variantById('scent-50')!.stock,
      1,
    );
  });
}
