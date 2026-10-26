import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/auth/domain/repositories/user_profile_repository.dart';

class SupabaseUserProfileRepository implements UserProfileRepository {
  SupabaseUserProfileRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<UserProfile?> findById(String userId) async {
    final row = await _client.from('customers').select().eq('id', userId).maybeSingle();
    return row == null ? null : _decode(row);
  }

  @override
  Stream<UserProfile?> watch(String userId) async* {
    yield await findById(userId);
    yield* Stream.periodic(const Duration(seconds: 30)).asyncMap((_) => findById(userId));
  }

  @override
  Future<void> save(UserProfile profile) async {
    await _client.rpc('ensure_customer_profile');
    await _client.from('customers').update({
      'email': profile.email,
      'display_name': profile.displayName,
    }).eq('id', profile.id);
  }

  UserProfile _decode(Map<String, dynamic> row) => UserProfile(
    id: row['id'] as String,
    email: (row['email'] as String?) ?? '',
    displayName: (row['display_name'] as String?) ?? '',
    role: UserRole.values.firstWhere((role) => role.wireValue == row['role'], orElse: () => UserRole.customer),
    createdAt: DateTime.tryParse((row['created_at'] as String?) ?? '') ?? DateTime.now(),
  );
}
