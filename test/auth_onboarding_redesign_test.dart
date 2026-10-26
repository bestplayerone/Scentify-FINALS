import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scentify/main.dart';
import 'package:scentify/ui/scentify_design_system.dart';

void main() {
  testWidgets('onboarding uses the new editorial layout without overflow', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.onboarding));

    expect(find.byKey(const Key('onboarding-hero-art')), findsOneWidget);
    expect(find.text('Discover your signature'), findsOneWidget);
    expect(find.text('Discover fragrances for every you.'), findsOneWidget);
    expect(find.byTooltip('Get started'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login keeps the compact fields and configured Google action', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));

    expect(find.byKey(const Key('auth-hero-art')), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('auth-email')), findsOneWidget);
    expect(find.byKey(const Key('auth-password')), findsOneWidget);
    final emailField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('auth-email')),
        matching: find.byType(TextField),
      ),
    );
    final passwordField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('auth-password')),
        matching: find.byType(TextField),
      ),
    );
    expect(
      passwordField.decoration!.fillColor,
      emailField.decoration!.fillColor,
    );
    expect(
      passwordField.decoration!.enabledBorder,
      emailField.decoration!.enabledBorder,
    );
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(const Key('google-logo')), findsOneWidget);
    expect(find.text('Continue with phone'), findsNothing);
    expect(find.byKey(const Key('auth-back')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Google login button invokes the configured auth flow', (
    WidgetTester tester,
  ) async {
    var wasPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthPage(
          onSubmit: ({
            required bool register,
            String? displayName,
            required String email,
            required String password,
          }) async {},
          onGoogleSignIn: () async {
            wasPressed = true;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pumpAndSettle();

    expect(wasPressed, isTrue);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Google sign-in stays legible in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.light(),
        darkTheme: ScentifyTheme.dark(),
        themeMode: ThemeMode.dark,
        home: AuthPage(
          onSubmit: ({
            required bool register,
            String? displayName,
            required String email,
            required String password,
          }) async {},
          onGoogleSignIn: () async {},
        ),
      ),
    );

    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('google-sign-in')),
    );
    final colors = ScentifyThemeColors.of(
      tester.element(find.byKey(const Key('google-sign-in'))),
    );
    expect(button.style?.backgroundColor?.resolve(const {}), Colors.white);
    expect(button.style?.foregroundColor?.resolve(const {}), colors.ink);
  });
}
