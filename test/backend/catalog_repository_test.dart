import 'dart:async';

import 'package:test/test.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/catalog/data/catalog_seed.dart';
import 'package:scentify/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';

void main() {
  final freshPerfume = Perfume(
    id: 'clean-reserve',
    brandId: 'brand-a',
    brandName: 'Maison Clean',
    name: 'Clean Reserve Skin',
    description: 'A bright, clean everyday scent.',
    gender: GenderPreference.unisex,
    family: FragranceFamily.fresh,
    concentration: Concentration.edp,
    occasions: [Occasion.everyday, Occasion.office],
    vibes: [ScentVibe.clean, ScentVibe.calming],
    topNotes: ['Pear'],
    heartNotes: ['Musk'],
    baseNotes: ['Amber'],
    variants: [
      PerfumeVariant(
        id: 'clean-50',
        label: '50ml',
        volumeMl: 50,
        price: Money(5_500_00),
        stock: 3,
      ),
    ],
    tags: ['fresh', 'office'],
  );

  final woodyPerfume = Perfume(
    id: 'bold-wood',
    brandId: 'brand-b',
    brandName: 'Atelier Bold',
    name: 'Bold Wood',
    description: 'A deep evening fragrance.',
    gender: GenderPreference.men,
    family: FragranceFamily.woody,
    concentration: Concentration.parfum,
    occasions: [Occasion.evening],
    vibes: [ScentVibe.bold, ScentVibe.mysterious],
    topNotes: ['Pepper'],
    heartNotes: ['Cedar'],
    baseNotes: ['Leather'],
    variants: [
      PerfumeVariant(
        id: 'bold-100',
        label: '100ml',
        volumeMl: 100,
        price: Money(12_000_00),
        stock: 2,
      ),
    ],
  );

  test('catalog filters by search, gender, and price', () async {
    final repository = InMemoryCatalogRepository([freshPerfume, woodyPerfume]);

    final results = await repository.list(
      filter: CatalogFilter(
        search: 'amber',
        gender: GenderPreference.unisex,
        maxPrice: Money(6_000_00),
      ),
    );

    expect(results.map((product) => product.id), ['clean-reserve']);
  });

  test('catalog stream emits initial and mutation snapshots', () async {
    final repository = InMemoryCatalogRepository([freshPerfume]);
    final iterator = StreamIterator(repository.watch());

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.map((product) => product.id), ['clean-reserve']);

    await repository.save(
      freshPerfume.copyWith(id: 'clean-reserve-2', name: 'Clean Reserve Rain'),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.map((product) => product.id), [
      'clean-reserve-2',
      'clean-reserve',
    ]);

    await repository.delete('clean-reserve');
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.map((product) => product.id), ['clean-reserve-2']);

    await iterator.cancel();
  });

  test(
    'additional catalog seed contains forty unique publishable products',
    () {
      expect(additionalCatalogSeed, hasLength(40));
      expect(
        additionalCatalogSeed.map((product) => product.id).toSet(),
        hasLength(40),
      );
      expect(
        additionalCatalogSeed.every(
          (product) => product.isPublished && product.variants.isNotEmpty,
        ),
        isTrue,
      );
    },
  );
}
