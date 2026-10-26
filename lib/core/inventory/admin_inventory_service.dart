import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:scentify/features/catalog/data/supabase_catalog_repository.dart';
import 'package:scentify/features/catalog/data/firestore_catalog_repository.dart';

class AdminInventoryService {
  AdminInventoryService(this._catalogRepository);

  final CatalogRepository _catalogRepository;

  Stream<List<Map<String, dynamic>>> watchRecentChanges() {
    final repository = _catalogRepository;
    if (repository is FirestoreCatalogRepository) {
      return repository.watchInventoryAdjustments();
    }
    return const Stream.empty();
  }

  Future<void> restock({
    required UserProfile actor,
    required String productId,
    required String variantId,
    required int quantity,
  }) async {
    if (!actor.isAdmin) {
      throw const AuthorizationException('Only admins can restock inventory.');
    }
    if (quantity < 1 || quantity > 100000) {
      throw const ValidationException(
        'Restock quantity must be between 1 and 100,000.',
      );
    }
    await adjustStock(
      actor: actor,
      productId: productId,
      variantId: variantId,
      delta: quantity,
      reason: 'Admin restock',
    );
  }

  Future<void> adjustStock({
    required UserProfile actor,
    required String productId,
    required String variantId,
    required int delta,
    String reason = 'Admin stock adjustment',
  }) async {
    if (!actor.isAdmin) {
      throw const AuthorizationException('Only admins can adjust inventory.');
    }
    if (delta == 0 || delta.abs() > 100000) {
      throw const ValidationException(
        'Adjustment must be between -100,000 and 100,000.',
      );
    }
    final supabaseRepository = _catalogRepository;
    if (supabaseRepository is SupabaseCatalogRepository) {
      await supabaseRepository.adjustStock(
        variantId: variantId,
        delta: delta,
        reason: reason,
      );
      return;
    }
    if (supabaseRepository is FirestoreCatalogRepository) {
      await supabaseRepository.adjustStock(
        productId: productId,
        variantId: variantId,
        delta: delta,
        reason: reason,
      );
      return;
    }
    final product = await _catalogRepository.findById(productId);
    if (product == null) {
      throw const NotFoundException('The inventory product does not exist.');
    }
    final variant = product.variantById(variantId);
    if (variant == null) {
      throw const NotFoundException('The inventory variant does not exist.');
    }
    if (variant.stock + delta < 0) {
      throw const ValidationException('Stock cannot be negative.');
    }
    await _catalogRepository.save(
      product.copyWith(
        variants: [
          for (final candidate in product.variants)
            candidate.id == variantId
                ? candidate.copyWith(stock: candidate.stock + delta)
                : candidate,
        ],
      ),
    );
  }
}
