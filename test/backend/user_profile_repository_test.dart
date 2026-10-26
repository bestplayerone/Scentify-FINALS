import 'dart:async';

import 'package:test/test.dart';
import 'package:scentify/features/auth/data/in_memory_user_profile_repository.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';

void main() {
  test('profile stream emits the current profile and later updates', () async {
    final repository = InMemoryUserProfileRepository();
    final initial = UserProfile(
      id: 'customer-1',
      email: 'customer@example.com',
      displayName: 'Ava Santos',
      role: UserRole.customer,
      createdAt: DateTime(2026, 10, 1),
    );
    final updated = initial.copyWith(displayName: 'Ava Rivera');
    final iterator = StreamIterator(repository.watch(initial.id));

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isNull);

    await repository.save(initial);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current?.displayName, 'Ava Santos');

    await repository.save(updated);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current?.displayName, 'Ava Rivera');

    await iterator.cancel();
  });
}
