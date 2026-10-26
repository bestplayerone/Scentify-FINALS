import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/main.dart';

void main() {
  test('normalizes Philippine mobile numbers to the stored +63 form', () {
    expect(normalizePhilippineMobileNumber('09171234567'), '+639171234567');
    expect(normalizePhilippineMobileNumber('+639171234567'), '+639171234567');
    expect(normalizePhilippineMobileNumber('0917 123-4567'), '+639171234567');
    expect(
      normalizePhilippineMobileNumber('+63 (917) 123-4567'),
      '+639171234567',
    );
    expect(normalizePhilippineMobileNumber('0917123456'), isNull);
    expect(normalizePhilippineMobileNumber('+14155550123'), isNull);
  });

  test('normalizes Manila province entry to NCR for an NCR city', () {
    final address = ShippingAddress(
      fullName: 'Juan Dela Cruz',
      phoneNumber: '09171234567',
      addressLine1: '132 Mabini Street',
      barangay: 'Barangay 132',
      city: 'Caloocan City',
      province: 'Manila',
      postalCode: '1400',
    );

    expect(address.province, 'National Capital Region');
  });

  test('keeps Manila unnormalized for a non-NCR city', () {
    final address = ShippingAddress(
      fullName: 'Juan Dela Cruz',
      phoneNumber: '09171234567',
      addressLine1: '1 Main Street',
      barangay: 'Barangay 1',
      city: 'Cebu City',
      province: 'Manila',
      postalCode: '6000',
    );

    expect(address.province, 'Manila');
  });
}
