import 'dart:async';

import 'package:scentify/features/checkout/domain/models/saved_address.dart';
import 'package:scentify/features/checkout/domain/repositories/saved_address_repository.dart';

class InMemorySavedAddressRepository implements SavedAddressRepository {
  final Map<String, SavedAddress> _addresses = {};
  final _changes = StreamController<String>.broadcast();

  @override
  Future<SavedAddress?> findForUser(String userId) async => _addresses[userId];

  @override
  Stream<SavedAddress?> watchForUser(String userId) {
    late final StreamSubscription<String> subscription;
    final controller = StreamController<SavedAddress?>(sync: true);
    controller.onListen = () {
      subscription = _changes.stream
          .where((changedUserId) => changedUserId == userId)
          .listen((_) => controller.add(_addresses[userId]));
      controller.add(_addresses[userId]);
    };
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  @override
  Future<void> saveForUser(String userId, SavedAddress address) async {
    _addresses[userId] = address;
    _changes.add(userId);
  }

  @override
  Future<void> deleteForUser(String userId) async {
    _addresses.remove(userId);
    _changes.add(userId);
  }
}
