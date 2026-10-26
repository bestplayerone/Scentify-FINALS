import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/main.dart';
import 'package:scentify/ui/scentify_design_system.dart';

const _product = Product(
  id: 'visual-review-product',
  name: 'Coco Mademoiselle Eau de Parfum',
  brand: 'Chanel',
  price: 8900,
  volume: '50ml',
  description: 'A bright amber floral with citrus and a warm patchouli finish.',
  imageUrls: ['https://example.com/coco-side.png'],
);

Widget _reviewProduct({bool dark = false, double textScale = 1}) {
  const productPage = ProductPage(
    product: _product,
    isFavorite: false,
    onBack: _noop,
    onFavorite: _noop,
    onAddToCart: _noopAdd,
  );
  return MaterialApp(
    theme: dark ? ScentifyTheme.dark() : ScentifyTheme.light(),
    home: textScale == 1
        ? productPage
        : Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: productPage,
            ),
          ),
  );
}

Finder _containerWithColor(Color color) => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.decoration is BoxDecoration &&
      (widget.decoration! as BoxDecoration).color == color,
);

void main() {
  testWidgets('product detail surfaces follow dark theme semantic colors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_reviewProduct(dark: true));

    final context = tester.element(
      find.byKey(const Key('product-detail-page')),
    );
    final colors = ScentifyThemeColors.of(context);
    final page = find.byKey(const Key('product-detail-page'));

    expect(
      find.descendant(of: page, matching: _containerWithColor(colors.field)),
      findsOneWidget,
      reason: 'the gallery surface should use the dark field color',
    );
    final unselectedSize = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('product-size-100ml')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect((unselectedSize.decoration as BoxDecoration).color, colors.paper);
    expect(
      find.descendant(
        of: find.byKey(const Key('product-purchase-bar')),
        matching: _containerWithColor(colors.paper),
      ),
      findsOneWidget,
    );

    final noteLabel = tester.widget<Text>(find.text('Top Notes'));
    expect(noteLabel.style?.color, colors.muted);
    final wishlistButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.favorite_border_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(wishlistButton.style?.backgroundColor?.resolve({}), colors.paper);
  });

  testWidgets('product image indicators have accessible touch targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ScentifyTheme.light(),
        home: Scaffold(
          body: Center(
            child: ProductImageCarousel(product: _product, imageSize: 204),
          ),
        ),
      ),
    );

    for (var index = 0; index < 2; index++) {
      final target = tester.getSize(
        find.byKey(ValueKey('product-image-dot-$index')),
      );
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('product detail remains usable at large text on a small phone', (
    tester,
  ) async {
    const phone = Size(320, 568);
    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_reviewProduct(textScale: 2));

    expect(find.byKey(const Key('product-add-to-cart')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('product-add-to-cart'))).bottom,
      lessThanOrEqualTo(phone.height),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('size choices remain readable when phone text is enlarged', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_reviewProduct(textScale: 2));

    await tester.scrollUntilVisible(
      find.byKey(const Key('product-size-150ml')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    for (final volume in ['50ml', '100ml', '150ml']) {
      final choice = find.byKey(ValueKey('product-size-$volume'));
      expect(choice, findsOneWidget);
      expect(tester.getSize(choice).width, greaterThanOrEqualTo(120));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('product detail does not expose a nonfunctional share action', (
    tester,
  ) async {
    await tester.pumpWidget(_reviewProduct());
    expect(find.byTooltip('Share'), findsNothing);
  });

  testWidgets('desktop product detail balances the gallery and product info', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_reviewProduct());

    final galleryFrame = tester.getRect(
      find.byKey(const Key('product-gallery-frame')),
    );
    final title = tester.getRect(find.text(_product.name));
    final notes = tester.getRect(find.text('Fragrance Notes'));

    expect(galleryFrame.width, lessThanOrEqualTo(600));
    expect(title.top, lessThan(galleryFrame.bottom));
    expect(notes.left, greaterThan(galleryFrame.right));
    expect(notes.top, lessThan(galleryFrame.bottom));
    final purchaseAction = tester.getRect(
      find.byKey(const Key('product-add-to-cart')),
    );
    expect(purchaseAction.width, lessThanOrEqualTo(720));
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

void _noopAdd(int quantity, String volume) {}
