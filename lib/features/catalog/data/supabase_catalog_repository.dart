import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<Perfume>> list({CatalogFilter filter = const CatalogFilter()}) async {
    final rows = await _client
        .from('products')
        .select('*, brands(name)')
        .eq('is_published', true);
    final variants = await _client.from('catalog_variants').select('*');
    return _decodeRows(rows, variants, filter);
  }

  @override
  Stream<List<Perfume>> watch({CatalogFilter filter = const CatalogFilter()}) async* {
    yield await list(filter: filter);
    yield* Stream.periodic(const Duration(seconds: 30))
        .asyncMap((_) => list(filter: filter));
  }

  @override
  Future<Perfume?> findById(String productId) async {
    final rows = await _client
        .from('products')
        .select('*, brands(name)')
        .eq('id', productId)
        .maybeSingle();
    if (rows == null) return null;
    final variants = await _client
        .from('catalog_variants')
        .select('*')
        .eq('product_id', productId);
    return _decode({...rows, 'catalog_variants': variants});
  }

  @override
  Future<void> save(Perfume product) async {
    await _client.from('products').update({
      'name': product.name,
      'description': product.description,
      'is_published': product.isPublished,
      'image_urls': product.imageUrls,
      'tags': product.tags,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', product.id);
    for (final variant in product.variants) {
      await _client.from('product_variants').update({
        'label': variant.label,
        'volume_ml': variant.volumeMl,
        'price_centavos': variant.price.centavos,
        'on_hand': variant.stock,
      }).eq('id', variant.id);
    }
  }

  @override
  Future<void> delete(String productId) async {
    await _client.from('products').delete().eq('id', productId);
  }

  Future<int> adjustStock({
    required String variantId,
    required int delta,
    required String reason,
  }) async {
    final result = await _client.rpc(
      'admin_adjust_stock',
      params: {
        'p_variant_id': variantId,
        'p_delta': delta,
        'p_reason': reason,
      },
    );
    return (result as num).toInt();
  }

  List<Perfume> _decodeRows(
    List<dynamic> rows,
    List<dynamic> variants,
    CatalogFilter filter,
  ) {
    final variantsByProduct = <String, List<dynamic>>{};
    for (final variant in variants.whereType<Map<String, dynamic>>()) {
      final productId = variant['product_id'];
      if (productId is String) {
        variantsByProduct.putIfAbsent(productId, () => []).add(variant);
      }
    }
    final products = rows
        .whereType<Map<String, dynamic>>()
        .map((row) => _decode({
              ...row,
              'catalog_variants': variantsByProduct[row['id']] ?? const [],
            }))
        .where((product) => _matches(product, filter))
        .toList();
    products.sort((left, right) => left.name.compareTo(right.name));
    return products;
  }

  Perfume _decode(Map<String, dynamic> row) {
    final brand = row['brands'];
    final variants = (row['catalog_variants'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (variant) => PerfumeVariant(
            id: _string(variant['id']),
            label: _string(variant['label']),
            volumeMl: _integer(variant['volume_ml']),
            price: Money(_integer(variant['price_centavos'])),
            stock: _integer(variant['available'] ?? variant['on_hand']),
          ),
        )
        .toList();
    return Perfume(
      id: _string(row['id']),
      brandId: _string(row['brand_id']),
      brandName: brand is Map<String, dynamic>
          ? _string(brand['name'])
          : _string(row['brand_id']),
      name: _string(row['name']),
      description: _string(row['description']),
      gender: _gender(row['gender']),
      family: _family(row['family']),
      concentration: _concentration(row['concentration']),
      occasions: _enumList(row['occasions'], Occasion.values),
      vibes: _enumList(row['vibes'], ScentVibe.values),
      topNotes: _stringList(row['top_notes']),
      heartNotes: _stringList(row['heart_notes']),
      baseNotes: _stringList(row['base_notes']),
      variants: variants,
      imageUrls: _stringList(row['image_urls']),
      tags: _stringList(row['tags']),
      authenticityNote: _string(row['authenticity_note']),
      isPublished: row['is_published'] == true,
    );
  }

  bool _matches(Perfume product, CatalogFilter filter) {
    if (filter.availableOnly && !product.hasAvailableStock) return false;
    if (filter.brandId != null && product.brandId != filter.brandId) return false;
    if (filter.gender != null && product.gender != filter.gender) return false;
    if (filter.family != null && product.family != filter.family) return false;
    if (filter.concentration != null && product.concentration != filter.concentration) return false;
    if (filter.occasion != null && !product.occasions.contains(filter.occasion)) return false;
    if (filter.vibe != null && !product.vibes.contains(filter.vibe)) return false;
    final query = filter.search?.trim().toLowerCase();
    if (query != null && query.isNotEmpty &&
        ![product.name, product.brandName, product.description, ...product.tags]
            .join(' ').toLowerCase().contains(query)) return false;
    return true;
  }

  T _enumValue<T extends Enum>(String? value, List<T> values, T fallback) {
    for (final item in values) {
      if (item.name == value) return item;
    }
    return fallback;
  }

  GenderPreference _gender(Object? value) => _enumValue(
    value as String?,
    GenderPreference.values,
    GenderPreference.unisex,
  );

  FragranceFamily _family(Object? value) => _enumValue(
    value as String?,
    FragranceFamily.values,
    FragranceFamily.fresh,
  );

  Concentration _concentration(Object? value) => _enumValue(
    value as String?,
    Concentration.values,
    Concentration.edp,
  );

  List<T> _enumList<T extends Enum>(Object? value, List<T> values) {
    if (value is! List) return const [];
    return value.whereType<String>().map((item) => _enumValue(item, values, values.first)).toList();
  }

  List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  String _string(Object? value) => value is String ? value : '';

  int _integer(Object? value) => value is int ? value : (value as num?)?.toInt() ?? 0;
}
