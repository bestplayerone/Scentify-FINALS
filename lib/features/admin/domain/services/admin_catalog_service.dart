import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';

class AdminCatalogService {
  AdminCatalogService(this._catalogRepository);

  final CatalogRepository _catalogRepository;

  Future<void> saveProduct({
    required UserProfile actor,
    required Perfume product,
  }) async {
    _requireAdmin(actor);
    await _catalogRepository.save(product);
  }

  Future<void> deleteProduct({
    required UserProfile actor,
    required String productId,
  }) async {
    _requireAdmin(actor);
    await _catalogRepository.delete(productId);
  }

  void _requireAdmin(UserProfile actor) {
    if (!actor.isAdmin) {
      throw const AuthorizationException('Only admins can manage products.');
    }
  }
}
