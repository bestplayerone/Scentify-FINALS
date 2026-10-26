abstract interface class WishlistRepository {
  Future<Set<String>> findByUserId(String userId);

  Stream<Set<String>> watch(String userId);

  Future<void> save(String userId, Set<String> productIds);
}
