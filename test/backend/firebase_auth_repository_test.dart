import 'package:test/test.dart';
import 'package:scentify/features/auth/domain/auth_error_messages.dart';

void main() {
  test('maps authentication errors to safe user-facing messages', () {
    expect(
      firebaseAuthErrorMessage('wrong-password'),
      'Email or password is incorrect.',
    );
    expect(
      firebaseAuthErrorMessage('invalid-credential'),
      'Email or password is incorrect.',
    );
    expect(
      firebaseAuthErrorMessage('email-already-in-use'),
      'An account already exists for this email.',
    );
    expect(
      firebaseAuthErrorMessage('network-request-failed'),
      'Check your internet connection and try again.',
    );
    expect(
      firebaseAuthErrorMessage('popup-closed-by-user'),
      'Google sign-in was canceled.',
    );
    expect(
      firebaseAuthErrorMessage('account-exists-with-different-credential'),
      'This email already uses password login. Sign in with email and password instead.',
    );
  });
}
