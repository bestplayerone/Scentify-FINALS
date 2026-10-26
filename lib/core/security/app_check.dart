import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

const _webRecaptchaSiteKey = String.fromEnvironment(
  'SCENTIFY_RECAPTCHA_SITE_KEY',
);

/// Activates the provider that matches the current platform before any
/// Firestore or callable use. Register the release apps/providers in Firebase
/// Console first; debug providers are intended only for local/emulator builds.
Future<void> activateScentifyAppCheck({bool? debug}) async {
  final useDebugProvider = debug ?? kDebugMode;
  if (kIsWeb && !useDebugProvider && _webRecaptchaSiteKey.isEmpty) {
    throw StateError(
      'SCENTIFY_RECAPTCHA_SITE_KEY is required for release web App Check.',
    );
  }

  await FirebaseAppCheck.instance.activate(
    providerAndroid: useDebugProvider
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: useDebugProvider
        ? const AppleDebugProvider()
        : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    providerWeb: kIsWeb
        ? (useDebugProvider
              ? WebDebugProvider()
              : ReCaptchaV3Provider(_webRecaptchaSiteKey))
        : null,
    providerWindows: const WindowsDebugProvider(),
  );
}
