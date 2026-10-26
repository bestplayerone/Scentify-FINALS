import 'dart:async';

import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/auth/domain/repositories/user_profile_repository.dart';

class InMemoryUserProfileRepository implements UserProfileRepository {
  final Map<String, UserProfile> _profiles = {};
  final _changes = StreamController<String>.broadcast();

  @override
  Future<UserProfile?> findById(String userId) async => _profiles[userId];

  @override
  Stream<UserProfile?> watch(String userId) {
    late final StreamSubscription<String> subscription;
    final controller = StreamController<UserProfile?>(sync: true);
    controller.onListen = () {
      subscription = _changes.stream
          .where((changedUserId) => changedUserId == userId)
          .listen((_) => controller.add(_profiles[userId]));
      controller.add(_profiles[userId]);
    };
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  @override
  Future<void> save(UserProfile profile) async {
    _profiles[profile.id] = profile;
    _changes.add(profile.id);
  }
}
