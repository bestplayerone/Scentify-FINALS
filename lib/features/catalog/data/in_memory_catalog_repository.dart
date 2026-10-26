import 'dart:async';

import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';

class InMemoryCatalogRepository implements CatalogRepository {
  InMemoryCatalogRepository([Iterable<Perfume> products = const []])
    : _products = {for (final product in products) product.id: product};

  final Map<String, Perfume> _products;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<List<Perfume>> list({
    CatalogFilter filter = const CatalogFilter(),
  }) async {
    final results = _products.values.where((product) {
      if (!product.isPublished) {
        return false;
      }
      if (filter.brandId != null && product.brandId != filter.brandId) {
        return false;
      }
      if (filter.gender != null && product.gender != filter.gender) {
        return false;
      }
      if (filter.family != null && product.family != filter.family) {
        return false;
      }
      if (filter.concentration != null &&
          product.concentration != filter.concentration) {
        return false;
      }
      if (filter.occasion != null &&
          !product.occasions.contains(filter.occasion)) {
        return false;
      }
      if (filter.vibe != null && !product.vibes.contains(filter.vibe)) {
        return false;
      }
      if (filter.availableOnly && !product.hasAvailableStock) {
        return false;
      }
      if (filter.minPrice != null || filter.maxPrice != null) {
        final hasMatchingPrice = product.variants.any((variant) {
          final atLeastMinimum =
              filter.minPrice == null || variant.price >= filter.minPrice!;
          final atMostMaximum =
              filter.maxPrice == null || variant.price <= filter.maxPrice!;
          return atLeastMinimum && atMostMaximum;
        });
        if (!hasMatchingPrice) {
          return false;
        }
      }
      return _matchesSearch(product, filter.search);
    }).toList();

    results.sort((left, right) => left.name.compareTo(right.name));
    return results;
  }

  @override
  Stream<List<Perfume>> watch({CatalogFilter filter = const CatalogFilter()}) {
    late final StreamSubscription<void> subscription;
    final controller = StreamController<List<Perfume>>(sync: true);
    controller.onListen = () {
      subscription = _changes.stream.listen((_) async {
        controller.add(await list(filter: filter));
      });
      list(filter: filter).then(controller.add);
    };
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  bool _matchesSearch(Perfume product, String? search) {
    final query = search?.trim().toLowerCase();
    if (query == null || query.isEmpty) {
      return true;
    }

    final searchableText = [
      product.name,
      product.brandName,
      product.description,
      ...product.tags,
      ...product.topNotes,
      ...product.heartNotes,
      ...product.baseNotes,
    ].join(' ').toLowerCase();

    return searchableText.contains(query);
  }

  @override
  Future<Perfume?> findById(String productId) async => _products[productId];

  @override
  Future<void> save(Perfume product) async {
    _products[product.id] = product;
    _changes.add(null);
  }

  @override
  Future<void> delete(String productId) async {
    _products.remove(productId);
    _changes.add(null);
  }
}
