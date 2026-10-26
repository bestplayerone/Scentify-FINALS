import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scentify/features/auth/domain/auth_error_messages.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';

class SupabaseAuthFailure implements Exception {
  const SupabaseAuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabaseAuthRepository {
  SupabaseAuthRepository({SupabaseClient? client})
      : _auth = (client ?? Supabase.instance.client).auth;
  final GoTrueClient _auth;

  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUser?.id;

  Future<UserRole> claimRole({bool forceRefresh = false, User? user}) async {
    final value = (user ?? _auth.currentUser)?.appMetadata['role'];
    return value == 'superadmin'
        ? UserRole.superadmin
        : value == 'admin' ? UserRole.admin : UserRole.customer;
  }

  Future<User?> get restoredUser async => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (error) {
      throw SupabaseAuthFailure(
        supabaseAuthErrorMessage(error.code ?? '', error.message),
      );
    }
  }

  Future<bool> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim()},
      );
      return response.session != null;
    } on AuthException catch (error) {
      throw SupabaseAuthFailure(error.message);
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      await _auth.signInWithOAuth(OAuthProvider.google);
    } on AuthException catch (error) {
      throw SupabaseAuthFailure(error.message);
    }
  }

  Future<void> sendPasswordReset({required String email}) async {
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (error) {
      throw SupabaseAuthFailure(error.message);
    }
  }

  Future<void> signOut() => _auth.signOut();
}
