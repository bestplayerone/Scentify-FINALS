import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';

class InventoryRequest {
  InventoryRequest({
    required this.productId,
    required this.variantId,
    required this.quantity,
  }) {
    if (productId.isEmpty || variantId.isEmpty || quantity < 1) {
      throw const ValidationException('Inventory requests must be non-empty.');
    }
  }

  final String productId;
  final String variantId;
  final int quantity;
}

abstract interface class InventoryPort {
  Future<void> reserve(Iterable<InventoryRequest> requests);

  Future<void> release(Iterable<InventoryRequest> requests);
}

class InventoryService implements InventoryPort {
  InventoryService(this._catalogRepository);

  final CatalogRepository _catalogRepository;

  @override
  Future<void> reserve(Iterable<InventoryRequest> requests) =>
      _adjust(requests, -1);

  @override
  Future<void> release(Iterable<InventoryRequest> requests) =>
      _adjust(requests, 1);

  Future<void> _adjust(
    Iterable<InventoryRequest> requests,
    int direction,
  ) async {
    final grouped = <String, Map<String, int>>{};
    for (final request in requests) {
      final variants = grouped.putIfAbsent(request.productId, () => {});
      variants.update(
        request.variantId,
        (quantity) => quantity + (request.quantity * direction),
        ifAbsent: () => request.quantity * direction,
      );
    }

    final products = <String, Perfume>{};
    for (final productEntry in grouped.entries) {
      final product = await _catalogRepository.findById(productEntry.key);
      if (product == null) {
        throw const NotFoundException('The inventory product does not exist.');
      }
      products[product.id] = product;

      for (final variantEntry in productEntry.value.entries) {
        final variant = product.variantById(variantEntry.key);
        if (variant == null) {
          throw const NotFoundException(
            'The inventory variant does not exist.',
          );
        }
        final resultingStock = variant.stock + variantEntry.value;
        if (resultingStock < 0) {
          throw InsufficientStockException(
            'Insufficient stock for ${variant.label}.',
          );
        }
      }
    }

    for (final product in products.values) {
      final variantDeltas = grouped[product.id]!;
      final variants = product.variants.map((variant) {
        final delta = variantDeltas[variant.id] ?? 0;
        return delta == 0
            ? variant
            : variant.copyWith(stock: variant.stock + delta);
      }).toList();
      await _catalogRepository.save(product.copyWith(variants: variants));
    }
  }
}

/// Firestore checkout delegates stock mutation to the trusted payment webhook.
/// The client still validates that the requested variant exists; it must not
/// write catalog stock directly because catalog writes are admin/server-only.
class NoOpInventoryService implements InventoryPort {
  const NoOpInventoryService();

  @override
  Future<void> reserve(Iterable<InventoryRequest> requests) async {}

  @override
  Future<void> release(Iterable<InventoryRequest> requests) async {}
}
