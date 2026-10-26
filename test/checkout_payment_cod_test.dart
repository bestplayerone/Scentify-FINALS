import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/main.dart';

void main() {
  testWidgets('COD is presented as a cash collection option', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutPaymentPage(
          items: const <CartItem>[],
          products: const <Product>[],
          delivery: 'Standard Delivery',
          onBack: () {},
          onChangeAddress: () {},
          onChangeDelivery: () {},
          onPay: () async {},
          itemCount: 1,
          subtotal: Money(42000),
          shippingFee: Money(8000),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Cash on Delivery'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Cash on Delivery'), findsOneWidget);
    expect(
      find.text('Pay in cash when your confirmed order is delivered.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
  });

  testWidgets('GCash via Xendit can be selected', (tester) async {
    var selected = 'cod';
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutPaymentPage(
          items: const <CartItem>[],
          products: const <Product>[],
          delivery: 'Standard Delivery',
          onBack: () {},
          onChangeAddress: () {},
          onChangeDelivery: () {},
          onPay: () async {},
          itemCount: 1,
          subtotal: Money(42000),
          shippingFee: Money(8000),
          showXendit: true,
          onPaymentMethodChanged: (value) => selected = value,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('GCash'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('GCash'));
    expect(selected, 'gcash');
  });
}
