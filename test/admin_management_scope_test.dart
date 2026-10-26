import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/orders/data/in_memory_order_repository.dart';
import 'package:scentify/main.dart';

void main() {
  testWidgets(
    'admin modules clearly disclose read-only and unavailable tools',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final profile = UserProfile(
        id: 'superadmin-1',
        email: 'admin@example.com',
        displayName: 'Scentify Admin',
        role: UserRole.superadmin,
        createdAt: DateTime.utc(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AdminPage(
            orderRepository: InMemoryOrderRepository(),
            profile: profile,
            onLogout: () {},
            products: const [
              Product(
                id: 'product-1',
                name: 'Test Scent',
                brand: 'Test House',
                price: 420,
                stockByVolume: {'50ml': 3},
                stock: 3,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'admin dashboard layout');
      await tester.ensureVisible(find.text('Management modules'));
      await tester.pumpAndSettle();

      const readOnlyNotices = <String, String>{
        'products': 'Product editing and publishing are not available yet.',
        'inventory': 'Inventory adjustments are not available yet.',
        'customers':
            'Customer directory and profile management are not available yet.',
        'notifications':
            'Campaign authoring and manual dispatch are not available yet.',
        'settings': 'Store configuration cannot be changed from this screen.',
        'access': 'Admin staff management is not available yet.',
      };

      for (final entry in readOnlyNotices.entries) {
        final module = find.byKey(Key('admin-module-${entry.key}')).last;
        expect(module, findsOneWidget, reason: 'module ${entry.key}');
        await tester.ensureVisible(module);
        await tester.tap(module);
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      }
    },
  );
}
