import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/main.dart';
import 'package:scentify/ui/scentify_design_system.dart';

void main() {
  testWidgets('checkout progress uses semantic colors in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.dark(),
        home: const Scaffold(body: CheckoutSteps(active: 0)),
      ),
    );
    final context = tester.element(find.text('Address'));
    final colors = ScentifyThemeColors.of(context);
    expect(tester.widget<Text>(find.text('Address')).style?.color, colors.ink);
    expect(tester.widget<Text>(find.text('1')).style?.color, colors.canvas);
  });

  testWidgets('checkout progress fits a narrow phone without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.light(),
        home: const Scaffold(body: CheckoutSteps(active: 0)),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('checkout progress labels match the visible checkout stages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.light(),
        home: const Scaffold(body: CheckoutSteps(active: 1)),
      ),
    );
    expect(find.text('Delivery'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.light(),
        home: const Scaffold(body: CheckoutSteps(active: 2)),
      ),
    );
    expect(find.text('Review & Payment'), findsOneWidget);
  });

  testWidgets('checkout fields use readable dark surfaces and text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.dark(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: WireTextField(
              label: 'Full Name',
              icon: Icons.person_outline,
            ),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(TextField));
    final colors = ScentifyThemeColors.of(context);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.fillColor, colors.field);
    expect(field.style?.color, colors.ink);
  });

  testWidgets('checkout keyboard next action advances to the next field', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.light(),
        home: CheckoutAddressPage(onBack: _noop, onNext: (_) {}),
      ),
    );
    final firstField = find.byType(TextField).at(0);
    expect(
      tester.widget<TextField>(firstField).textInputAction,
      TextInputAction.next,
    );

    await tester.tap(firstField);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).at(1))
          .focusNode
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('checkout form stays readable on wide desktop windows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.light(),
        home: CheckoutAddressPage(onBack: _noop, onNext: (_) {}),
      ),
    );

    final form = tester.getRect(find.byKey(const Key('address-form')));
    final page = tester.getRect(find.byType(Scaffold).first);
    expect(form.width, lessThanOrEqualTo(840));
    expect((form.center.dx - page.center.dx).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('checkout keeps fields and its footer usable at larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.light(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: CheckoutAddressPage(onBack: _noop, onNext: (_) {}),
          ),
        ),
      ),
    );

    final button = find.text('Continue to Delivery');
    final buttonRect = tester.getRect(button);
    final pageRect = tester.getRect(find.byType(Scaffold).first);
    expect(
      tester.getSize(find.byType(TextField).first).height,
      greaterThan(48),
    );
    expect(buttonRect.bottom, lessThanOrEqualTo(pageRect.bottom));
  });
}

void _noop() {}
