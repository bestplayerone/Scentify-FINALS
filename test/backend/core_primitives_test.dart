import 'package:test/test.dart';
import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';

void main() {
  group('Money', () {
    test('uses integer centavos for exact arithmetic', () {
      final price = Money(12_500);

      expect((price + Money(2_500)).centavos, 15_000);
      expect((price * 2).centavos, 25_000);
      expect(price > Money(10_000), isTrue);
    });

    test('rejects negative values', () {
      expect(() => Money(-1), throwsA(isA<ValidationException>()));
    });
  });

  test('perfume variants can be copied without mutating the source', () {
    final original = PerfumeVariant(
      id: 'versace-50',
      label: '50ml',
      volumeMl: 50,
      price: Money(4_999_00),
      stock: 4,
    );

    final updated = original.copyWith(stock: 3);

    expect(original.stock, 4);
    expect(updated.stock, 3);
    expect(updated.price, original.price);
  });

  test('user profiles expose customer and admin roles', () {
    final customer = UserProfile(
      id: 'customer-1',
      email: 'customer@example.com',
      displayName: 'Customer',
      role: UserRole.customer,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final admin = customer.copyWith(role: UserRole.admin);
    final superadmin = customer.copyWith(role: UserRole.superadmin);

    expect(customer.isAdmin, isFalse);
    expect(admin.isAdmin, isTrue);
    expect(admin.isSuperAdmin, isFalse);
    expect(superadmin.isAdmin, isTrue);
    expect(superadmin.isSuperAdmin, isTrue);
    expect(superadmin.role.wireValue, 'superadmin');
  });
}
