import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:scentify/features/auth/domain/auth_error_messages.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';

const _googleServerClientId = String.fromEnvironment(
  'SCENTIFY_GOOGLE_SERVER_CLIENT_ID',
);

class FirebaseAuthFailure implements Exception {
  const FirebaseAuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirebaseAuthRepository {
  FirebaseAuthRepository({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _auth = auth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  static Future<void>? _googleSignInInitialization;

  User? get currentUser => _auth.currentUser;

  String? get currentUserId => _auth.currentUser?.uid;

  Future<UserRole> claimRole({bool forceRefresh = false, User? user}) async {
    final authenticatedUser = user ?? _auth.currentUser;
    if (authenticatedUser == null) {
      return UserRole.customer;
    }
    final token = await authenticatedUser.getIdTokenResult(forceRefresh);
    final claims = token.claims;
    if (claims?['superadmin'] == true) {
      return UserRole.superadmin;
    }
    if (claims?['admin'] == true) {
      return UserRole.admin;
    }
    return UserRole.customer;
  }

  Future<bool> hasAdminClaim({bool forceRefresh = false}) async {
    return (await claimRole(forceRefresh: forceRefresh)).isAdmin;
  }

  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        await _auth.signInWithPopup(GoogleAuthProvider());
        return;
      }

      try {
        _googleSignInInitialization ??= _googleSignIn.initialize(
          serverClientId: _googleServerClientId.isEmpty
              ? null
              : _googleServerClientId,
        );
        await _googleSignInInitialization;
      } catch (_) {
        _googleSignInInitialization = null;
        rethrow;
      }

      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const FirebaseAuthFailure(
          'Google sign-in did not return a valid identity token.',
        );
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthFailure {
      rethrow;
    } on GoogleSignInException catch (error) {
      final message = error.code == GoogleSignInExceptionCode.canceled
          ? 'Google sign-in was canceled.'
          : 'Google sign-in failed. Please try again.';
      throw FirebaseAuthFailure(message);
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(firebaseAuthErrorMessage(error.code));
    }
  }

  Future<User?> get restoredUser async {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      return currentUser;
    }
    return _auth.authStateChanges().first;
  }

  Future<String?> get restoredUserId async {
    return (await restoredUser)?.uid;
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(firebaseAuthErrorMessage(error.code));
    }
  }

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null && displayName.trim().isNotEmpty) {
        try {
          await user.updateDisplayName(displayName.trim());
        } on FirebaseAuthException {
          // Authentication succeeded; display name is optional metadata.
        }
      }
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(firebaseAuthErrorMessage(error.code));
    }
  }

  Future<void> sendPasswordReset({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(firebaseAuthErrorMessage(error.code));
    }
  }

  Future<void> signOut() => _auth.signOut();
}
