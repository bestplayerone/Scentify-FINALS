const firebaseAuthConfiguredPlatformsMessage =
    'Firebase Auth is configured for Android and Web. '
    'Run Scentify on Android or Chrome.';

String firebaseAuthErrorMessage(String code) => switch (code) {
  'invalid-email' => 'Enter a valid email address.',
  'user-disabled' => 'This account has been disabled.',
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' ||
  'invalid-login-credentials' => 'Email or password is incorrect.',
  'email-already-in-use' => 'An account already exists for this email.',
  'weak-password' => 'Use a stronger password with at least 6 characters.',
  'operation-not-allowed' =>
    'Email/password sign-in is not enabled in Firebase.',
  'network-request-failed' => 'Check your internet connection and try again.',
  'popup-closed-by-user' => 'Google sign-in was canceled.',
  'popup-blocked' => 'Allow the sign-in popup and try again.',
  'account-exists-with-different-credential' => 'This email already uses password login. Sign in with email and password instead.',
  _ => 'Authentication failed. Please try again.',
};
