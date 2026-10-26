import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:scentify/core/firebase/firestore_codecs.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';

class FirestoreCatalogRepository implements CatalogRepository {
  FirestoreCatalogRepository({
    FirebaseFirestore? firestore,
    String collectionName = 'perfumes',
  }) : _collection = (firestore ?? FirebaseFirestore.instance).collection(
         collectionName,
       );

  final CollectionReference<Map<String, dynamic>> _collection;

  Future<void> adjustStock({
    required String productId,
    required String variantId,
    required int delta,
    required String reason,
  }) async {
    await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('adjustInventory')
        .call<void>({
          'productId': productId,
          'variantId': variantId,
          'delta': delta,
          'reason': reason,
        });
  }

  Stream<List<Map<String, dynamic>>> watchInventoryAdjustments() => _collection
      .firestore
      .collection('inventoryAdjustments')
      .orderBy('createdAt', descending: true)
      .limit(10)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());

  @override
  Future<List<Perfume>> list({
    CatalogFilter filter = const CatalogFilter(),
  }) async {
    final snapshot = await _collection
        .where('isPublished', isEqualTo: true)
        .get();
    final products = snapshot.docs
        .map(
          (document) =>
              FirestoreCodecs.perfumeFromMap(document.id, document.data()),
        )
        .where((product) => _matchesFilter(product, filter))
        .toList();
    products.sort((left, right) => left.name.compareTo(right.name));
    return products;
  }

  @override
  Stream<List<Perfume>> watch({CatalogFilter filter = const CatalogFilter()}) {
    return _collection.where('isPublished', isEqualTo: true).snapshots().map((
      snapshot,
    ) {
      final products = snapshot.docs
          .map(
            (document) =>
                FirestoreCodecs.perfumeFromMap(document.id, document.data()),
          )
          .where((product) => _matchesFilter(product, filter))
          .toList();
      products.sort((left, right) => left.name.compareTo(right.name));
      return products;
    });
  }

  @override
  Future<Perfume?> findById(String productId) async {
    final document = await _collection.doc(productId).get();
    if (!document.exists || document.data() == null) {
      return null;
    }
    return FirestoreCodecs.perfumeFromMap(productId, document.data()!);
  }

  @override
  Future<void> save(Perfume product) {
    return _collection
        .doc(product.id)
        .set(FirestoreCodecs.perfumeToMap(product));
  }

  @override
  Future<void> delete(String productId) => _collection.doc(productId).delete();

  bool _matchesFilter(Perfume product, CatalogFilter filter) {
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
}
