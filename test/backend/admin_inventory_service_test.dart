import 'package:test/test.dart';
import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/inventory/admin_inventory_service.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';

void main() {
  test('admin restock increases only the selected variant', () async {
    final repository = InMemoryCatalogRepository([
      Perfume(
        id: 'product-1',
        brandId: 'brand-1',
        brandName: 'Test House',
        name: 'Test Scent',
        description: '',
        gender: GenderPreference.unisex,
        family: FragranceFamily.fresh,
        concentration: Concentration.edp,
        occasions: const [],
        vibes: const [],
        topNotes: const [],
        heartNotes: const [],
        baseNotes: const [],
        variants: [
          PerfumeVariant(
            id: '50ml',
            label: '50ml',
            volumeMl: 50,
            price: Money(42000),
            stock: 0,
          ),
          PerfumeVariant(
            id: '100ml',
            label: '100ml',
            volumeMl: 100,
            price: Money(62000),
            stock: 3,
          ),
        ],
      ),
    ]);
    final service = AdminInventoryService(repository);
    final admin = UserProfile(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: UserRole.admin,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await service.restock(
      actor: admin,
      productId: 'product-1',
      variantId: '50ml',
      quantity: 7,
    );

    final product = await repository.findById('product-1');
    expect(product!.variantById('50ml')!.stock, 7);
    expect(product.variantById('100ml')!.stock, 3);
  });

  test('customers cannot restock inventory', () async {
    final service = AdminInventoryService(InMemoryCatalogRepository());
    final customer = UserProfile(
      id: 'customer-1',
      email: 'customer@example.com',
      displayName: 'Customer',
      role: UserRole.customer,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    expect(
      () => service.restock(
        actor: customer,
        productId: 'missing',
        variantId: '50ml',
        quantity: 1,
      ),
      throwsA(isA<AuthorizationException>()),
    );
  });

  test(
    'admin can apply a signed variant adjustment without going below zero',
    () async {
      final repository = InMemoryCatalogRepository([
        Perfume(
          id: 'product-1',
          brandId: 'brand-1',
          brandName: 'Test House',
          name: 'Test Scent',
          description: '',
          gender: GenderPreference.unisex,
          family: FragranceFamily.fresh,
          concentration: Concentration.edp,
          occasions: const [],
          vibes: const [],
          topNotes: const [],
          heartNotes: const [],
          baseNotes: const [],
          variants: [
            PerfumeVariant(
              id: '50ml',
              label: '50ml',
              volumeMl: 50,
              price: Money(42000),
              stock: 5,
            ),
          ],
        ),
      ]);
      final admin = UserProfile(
        id: 'admin-1',
        email: 'admin@example.com',
        displayName: 'Admin',
        role: UserRole.admin,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final service = AdminInventoryService(repository);

      await service.adjustStock(
        actor: admin,
        productId: 'product-1',
        variantId: '50ml',
        delta: -2,
      );
      expect(
        (await repository.findById('product-1'))!.variantById('50ml')!.stock,
        3,
      );
      await expectLater(
        service.adjustStock(
          actor: admin,
          productId: 'product-1',
          variantId: '50ml',
          delta: -4,
        ),
        throwsA(isA<ValidationException>()),
      );
    },
  );
}
