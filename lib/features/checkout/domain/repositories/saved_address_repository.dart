import 'package:scentify/features/checkout/domain/models/saved_address.dart';

abstract interface class SavedAddressRepository {
  Future<SavedAddress?> findForUser(String userId);

  Stream<SavedAddress?> watchForUser(String userId);

  Future<void> saveForUser(String userId, SavedAddress address);

  Future<void> deleteForUser(String userId);
}
