import 'dart:async';

import 'package:test/test.dart';
import 'package:scentify/features/wishlist/data/in_memory_wishlist_repository.dart';
import 'package:scentify/features/wishlist/domain/services/wishlist_service.dart';

void main() {
  test(
    'wishlist toggle persists and emits customer-scoped snapshots',
    () async {
      final repository = InMemoryWishlistRepository();
      final service = WishlistService(repository);
      final snapshots = StreamIterator(repository.watch('customer-1'));

      expect(await snapshots.moveNext(), isTrue);
      expect(snapshots.current, isEmpty);

      expect(await service.toggle(userId: 'customer-1', productId: 'scent-1'), {
        'scent-1',
      });
      expect(await snapshots.moveNext(), isTrue);
      expect(snapshots.current, {'scent-1'});

      expect(
        await service.toggle(userId: 'customer-1', productId: 'scent-1'),
        isEmpty,
      );
      expect(await snapshots.moveNext(), isTrue);
      expect(snapshots.current, isEmpty);
      await snapshots.cancel();
    },
  );
}
