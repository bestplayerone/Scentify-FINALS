import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/ui/scentify_design_system.dart';

Widget shell(
  Widget child, {
  bool reducedMotion = false,
  bool dark = false,
  double textScale = 1,
}) => MaterialApp(
  theme: dark ? ScentifyTheme.dark() : ScentifyTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reducedMotion,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: Center(child: SizedBox(width: 280, child: child)),
    ),
  ),
);

double scale(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(ScentifyPressScale).first,
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .storage[0];

void main() {
  testWidgets('press reverses from its current scale without jumping', (
    tester,
  ) async {
    var commits = 0;
    await tester.pumpWidget(
      shell(
        ScentifyPrimaryButton(label: 'Continue', onPressed: () => commits++),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Continue')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final pressedScale = scale(tester);
    expect(pressedScale, lessThan(1));
    expect(commits, 0);
    await gesture.up();
    await tester.pump();
    expect(scale(tester), closeTo(pressedScale, 0.0001));
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(1, 0.001));
    expect(commits, 1);
  });

  testWidgets('dragging away releases visual feedback without committing', (
    tester,
  ) async {
    var commits = 0;
    await tester.pumpWidget(
      shell(
        ScentifyPrimaryButton(label: 'Continue', onPressed: () => commits++),
      ),
    );
    final center = tester.getCenter(find.text('Continue'));
    final gesture = await tester.startGesture(center);
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(0.97, 0.001));
    await gesture.moveTo(center + const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(1, 0.001));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(commits, 0);
  });

  testWidgets('disabled actions stay stationary', (tester) async {
    await tester.pumpWidget(
      shell(const ScentifyPrimaryButton(label: 'Continue', onPressed: null)),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Continue')),
    );
    await tester.pumpAndSettle();
    expect(scale(tester), 1);
    await gesture.cancel();
  });

  testWidgets('reduced motion keeps press feedback stationary', (tester) async {
    await tester.pumpWidget(
      shell(
        ScentifyPrimaryButton(label: 'Continue', onPressed: () {}),
        reducedMotion: true,
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Continue')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(scale(tester), 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('primary label inherits the dark theme foreground', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        ScentifyPrimaryButton(label: 'Continue', onPressed: () {}),
        dark: true,
      ),
    );
    final element = tester.element(find.text('Continue'));
    final text = tester.widget<Text>(find.text('Continue'));
    final color = DefaultTextStyle.of(element).style.merge(text.style).color;
    expect(color, Theme.of(element).colorScheme.onPrimary);
  });

  testWidgets('primary action grows and wraps with larger text', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        ScentifyPrimaryButton(
          label: 'Continue to secure checkout',
          onPressed: () {},
        ),
        textScale: 2,
      ),
    );
    expect(tester.getSize(find.byType(ElevatedButton)).height, greaterThan(52));
    expect(
      tester.widget<Text>(find.text('Continue to secure checkout')).maxLines,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected chip uses the theme selected surface in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        ScentifySelectableChip(label: 'Unisex', selected: true, onTap: () {}),
        dark: true,
      ),
    );
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(ScentifySelectableChip),
            matching: find.byType(Material),
          )
          .first,
    );
    final context = tester.element(find.text('Unisex'));
    final colors = ScentifyThemeColors.of(context);
    expect(material.color, colors.selected);
    expect(
      tester.widget<Text>(find.text('Unisex')).style!.color,
      colors.ink,
    );
    expect(find.byType(ScentifyPressScale), findsOneWidget);
  });
}
