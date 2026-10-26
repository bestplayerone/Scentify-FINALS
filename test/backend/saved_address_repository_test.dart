import 'dart:async';

import 'package:test/test.dart';
import 'package:scentify/features/checkout/data/in_memory_saved_address_repository.dart';
import 'package:scentify/features/checkout/domain/models/saved_address.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';

void main() {
  test(
    'saved address is user-scoped and watch emits save and delete',
    () async {
      final repository = InMemorySavedAddressRepository();
      final address = SavedAddress(
        id: 'primary',
        address: ShippingAddress(
          fullName: 'Juan Dela Cruz',
          phoneNumber: '09171234567',
          addressLine1: '123 Mabini Street',
          barangay: 'Barangay 1',
          city: 'Quezon City',
          province: 'Metro Manila',
          postalCode: '1100',
        ),
        label: 'Home',
        isDefault: true,
        latitude: 14.676,
        longitude: 121.0437,
        placeId: 'place-1',
        addressSource: 'autocomplete',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final iterator = StreamIterator(repository.watchForUser('customer-1'));

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isNull);

      await repository.saveForUser('customer-1', address);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current?.address.city, 'Quezon City');
      expect(iterator.current?.placeId, 'place-1');
      expect(await repository.findForUser('other-customer'), isNull);

      await repository.deleteForUser('customer-1');
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isNull);
      await iterator.cancel();
    },
  );
}
