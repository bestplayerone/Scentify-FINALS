import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/main.dart';

void main() {
  testWidgets('hero remains on the current slide until the user swipes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeHeroCarousel(
            cartCount: 0,
            notificationCount: 0,
            onCart: _noop,
            onNotifications: _noop,
            onBrowse: _noop,
            onTopPicks: _noop,
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-hero-dot-0'))).height,
      greaterThanOrEqualTo(48),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 300));

    final pageView = tester.widget<PageView>(
      find.byKey(const Key('home-hero-carousel')),
    );
    final controller = pageView.controller!;
    expect(controller.page, 0);
  });

  testWidgets('hero still follows a deliberate swipe', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeHeroCarousel(
            cartCount: 0,
            notificationCount: 0,
            onCart: _noop,
            onNotifications: _noop,
            onBrowse: _noop,
            onTopPicks: _noop,
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const Key('home-hero-carousel')),
      const Offset(-280, 0),
    );
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(
      find.byKey(const Key('home-hero-carousel')),
    );
    expect(pageView.controller!.page, 1);
  });

  testWidgets('category shortcut fits its reserved row at larger text sizes', (
    tester,
  ) async {
    for (final (scale, height) in [(1.0, 90.0), (2.0, 122.0)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 65,
                  height: height,
                  child: CategoryShortcut(label: 'For Her', onTap: _noop),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'text scale $scale');
    }
  });
}

void _noop() {}
