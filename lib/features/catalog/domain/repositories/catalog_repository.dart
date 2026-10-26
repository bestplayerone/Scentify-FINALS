import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';

abstract interface class CatalogRepository {
  Future<List<Perfume>> list({CatalogFilter filter = const CatalogFilter()});

  Stream<List<Perfume>> watch({CatalogFilter filter = const CatalogFilter()});

  Future<Perfume?> findById(String productId);

  Future<void> save(Perfume product);

  Future<void> delete(String productId);
}

class CatalogFilter {
  const CatalogFilter({
    this.search,
    this.brandId,
    this.gender,
    this.family,
    this.concentration,
    this.occasion,
    this.vibe,
    this.minPrice,
    this.maxPrice,
    this.availableOnly = true,
  });

  final String? search;
  final String? brandId;
  final GenderPreference? gender;
  final FragranceFamily? family;
  final Concentration? concentration;
  final Occasion? occasion;
  final ScentVibe? vibe;
  final Money? minPrice;
  final Money? maxPrice;
  final bool availableOnly;
}
