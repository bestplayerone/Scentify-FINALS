import 'package:scentify/features/auth/domain/models/user_profile.dart';

abstract interface class UserProfileRepository {
  Future<UserProfile?> findById(String userId);

  Stream<UserProfile?> watch(String userId);

  Future<void> save(UserProfile profile);
}
