import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/core/addresses/address_autocomplete_api.dart';
import 'package:scentify/features/checkout/domain/models/saved_address.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/main.dart';

void main() {
  testWidgets('checkout address fields match the existing server limits', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(onBack: () {}, onNext: (_) {}),
      ),
    );

    final fields = tester.widgetList<WireTextField>(find.byType(WireTextField));
    expect(fields.map((field) => field.maxLength), [
      120,
      32,
      240,
      120,
      120,
      120,
      4,
    ]);
  });

  testWidgets(
    'overlong autocomplete address is rejected before save or checkout',
    (tester) async {
      var saved = false;
      var continued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: CheckoutAddressPage(
            onBack: () {},
            onNext: (_) => continued = true,
            autocompleteProvider: _FakeAddressAutocompleteProvider(
              addressLine1: List.filled(241, 'A').join(),
            ),
            onSaveAddress: (_) async {
              saved = true;
            },
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('checkout-address-search')),
        'Mabini',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('address-suggestion-place-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to Delivery'));
      await tester.pumpAndSettle();

      expect(
        find.text('Address must be 240 characters or fewer.'),
        findsOneWidget,
      );
      expect(saved, isFalse);
      expect(continued, isFalse);
    },
  );

  testWidgets('saved address length is validated before checkout', (
    tester,
  ) async {
    var continued = false;
    final now = DateTime.utc(2026, 1, 1);
    final savedAddress = SavedAddress(
      id: 'primary',
      address: ShippingAddress(
        fullName: 'Juan Dela Cruz',
        phoneNumber: '09171234567',
        addressLine1: List.filled(241, 'A').join(),
        barangay: 'Barangay 1',
        city: 'Quezon City',
        province: 'Metro Manila',
        postalCode: '1100',
      ),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          onNext: (_) => continued = true,
          savedAddress: savedAddress,
        ),
      ),
    );

    await tester.tap(find.text('Deliver to this address'));
    await tester.pumpAndSettle();

    expect(continued, isFalse);
    expect(
      find.text('Address must be 240 characters or fewer.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('address-form')), findsOneWidget);
  });

  testWidgets('saved-address snapshot removal preserves the address draft', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1);
    SavedAddress? currentAddress = SavedAddress(
      id: 'primary',
      address: ShippingAddress(
        fullName: 'Juan Dela Cruz',
        phoneNumber: '+639171234567',
        addressLine1: '123 Mabini Street',
        barangay: 'Barangay 1',
        city: 'Quezon City',
        province: 'Metro Manila',
        postalCode: '1100',
      ),
      createdAt: now,
      updatedAt: now,
    );
    StateSetter? rebuildHost;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildHost = setState;
            return CheckoutAddressPage(
              onBack: () {},
              onNext: (_) {},
              savedAddress: currentAddress,
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Edit address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Maria Santos');
    currentAddress = null;
    rebuildHost!(() {});
    await tester.pumpAndSettle();

    final retainedValues = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller!.text)
        .toList();
    expect(retainedValues, contains('Maria Santos'));
    expect(retainedValues, contains('123 Mabini Street'));
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      '123 Mabini Street',
    );
  });

  testWidgets('failed optional address-book save does not block checkout', (
    tester,
  ) async {
    var saveAttempts = 0;
    ShippingAddress? continuedAddress;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          onNext: (address) => continuedAddress = address,
          onSaveAddress: (_) async {
            saveAttempts++;
            if (saveAttempts == 1) {
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
                message: 'A backend detail that must not reach the UI.',
              );
            }
          },
        ),
      ),
    );
    await _enterValidAddress(tester);

    await _tapSaveAddress(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Your account could not save this address. You can still continue checkout and retry later.',
      ),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const Key('address-form')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    final retainedValues = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller!.text)
        .toList();
    expect(retainedValues, contains('Maria Santos'));
    expect(retainedValues, contains('123 Mabini Street'));
    expect(continuedAddress, isNull);

    await _tapSaveAddress(tester);
    await tester.pumpAndSettle();

    expect(saveAttempts, 2);
    expect(continuedAddress, isNull);
    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();
    expect(continuedAddress?.addressLine1, '123 Mabini Street');
  });

  testWidgets('NCR address formats continue with inline checkout snapshot', (
    tester,
  ) async {
    var saveAttempts = 0;
    var continueAttempts = 0;
    String? selectedAddressId = 'primary';
    ShippingAddress? continuedAddress;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          onNext: (address) {
            continueAttempts++;
            continuedAddress = address;
          },
          onSavedAddressSelected: (id) => selectedAddressId = id,
          onSaveAddress: (_) async {
            saveAttempts++;
          },
        ),
      ),
    );
    await _enterValidAddress(tester);
    await tester.enterText(
      find.byType(TextField).at(3),
      'National Capital Region',
    );
    await tester.enterText(find.byType(TextField).at(4), 'Caloocan City');
    await tester.enterText(find.byType(TextField).at(5), 'Barangay 123');
    await tester.enterText(find.byType(TextField).at(6), '1400');

    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuing...'));
    await tester.pumpAndSettle();

    expect(saveAttempts, 0);
    expect(continueAttempts, 1);
    expect(selectedAddressId, isNull);
    expect(continuedAddress?.province, 'National Capital Region');
    expect(continuedAddress?.city, 'Caloocan City');
    expect(continuedAddress?.barangay, 'Barangay 123');
    expect(continuedAddress?.postalCode, '1400');
    expect(continuedAddress?.phoneNumber, '+639171234567');
  });

  testWidgets('profile address book still saves before returning', (
    tester,
  ) async {
    SavedAddress? persistedAddress;
    ShippingAddress? returnedAddress;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          onNext: (address) => returnedAddress = address,
          profileAddressBook: true,
          onSaveAddress: (address) async {
            persistedAddress = address;
          },
        ),
      ),
    );
    await _enterValidAddress(tester);

    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();

    expect(persistedAddress?.address.fullName, 'Maria Santos');
    expect(returnedAddress?.postalCode, '1100');
    expect(find.text('Save to My Addresses'), findsNothing);
  });

  testWidgets('missing ZIP code shows a field-specific required message', (
    tester,
  ) async {
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          onNext: (_) => continued = true,
        ),
      ),
    );
    await _enterValidAddress(tester);
    await tester.enterText(find.byType(TextField).at(6), '');
    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your ZIP code.'), findsOneWidget);
    expect(continued, isFalse);
  });

  testWidgets('repeated taps save an address-book entry only once', (
    tester,
  ) async {
    final saveCompleter = Completer<void>();
    var saveCalls = 0;
    var continueCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          onNext: (_) => continueCalls++,
          onSaveAddress: (_) {
            saveCalls++;
            return saveCompleter.future;
          },
        ),
      ),
    );
    await _enterValidAddress(tester);

    await _tapSaveAddress(tester);
    await tester.pump();
    await tester.tap(find.text('Saving to My Addresses…'));
    await tester.pump();

    expect(saveCalls, 1);
    saveCompleter.complete();
    await tester.pumpAndSettle();

    expect(continueCalls, 0);
    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();
    expect(continueCalls, 1);
  });

  testWidgets('manual checkout remains available when suggestions fail', (
    tester,
  ) async {
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          onNext: (_) => continued = true,
          autocompleteProvider: _FailingAddressAutocompleteProvider(),
        ),
      ),
    );
    await _enterValidAddress(tester);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Address suggestions are temporarily unavailable. You can still enter your address manually.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
  });

  testWidgets('editing a saved address preserves its hidden notes', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1);
    const notes = 'Leave the parcel at the front desk.';
    final existingAddress = SavedAddress(
      id: 'primary',
      address: ShippingAddress(
        fullName: 'Juan Dela Cruz',
        phoneNumber: '09171234567',
        addressLine1: '123 Mabini Street',
        barangay: 'Barangay 1',
        city: 'Quezon City',
        province: 'Metro Manila',
        postalCode: '1100',
        notes: notes,
      ),
      createdAt: now,
      updatedAt: now,
    );
    SavedAddress? persistedAddress;
    ShippingAddress? continuedAddress;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          savedAddress: existingAddress,
          onNext: (address) => continuedAddress = address,
          onSaveAddress: (address) async {
            persistedAddress = address;
          },
        ),
      ),
    );

    await tester.tap(find.text('Deliver to this address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Juan Rivera');
    await _tapSaveAddress(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();

    expect(continuedAddress?.notes, notes);
    expect(persistedAddress?.address.fullName, 'Juan Rivera');
    expect(persistedAddress?.address.notes, notes);
  });

  testWidgets('a new address does not inherit saved-address notes', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1);
    final existingAddress = SavedAddress(
      id: 'primary',
      address: ShippingAddress(
        fullName: 'Juan Dela Cruz',
        phoneNumber: '09171234567',
        addressLine1: '123 Mabini Street',
        barangay: 'Barangay 1',
        city: 'Quezon City',
        province: 'Metro Manila',
        postalCode: '1100',
        notes: 'Leave at the front desk.',
      ),
      createdAt: now,
      updatedAt: now,
    );
    SavedAddress? persistedAddress;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          savedAddress: existingAddress,
          onNext: (_) {},
          onSaveAddress: (address) async {
            persistedAddress = address;
          },
        ),
      ),
    );

    await tester.tap(find.text('+ Add new address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Maria Cruz');
    await tester.enterText(find.byType(TextField).at(1), '09171234567');
    await tester.enterText(find.byType(TextField).at(2), '456 Rizal Street');
    await tester.enterText(find.byType(TextField).at(3), 'Metro Manila');
    await tester.enterText(find.byType(TextField).at(4), 'Quezon City');
    await tester.enterText(find.byType(TextField).at(5), 'Barangay 2');
    await tester.enterText(find.byType(TextField).at(6), '1100');
    await _tapSaveAddress(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();

    expect(persistedAddress?.address.fullName, 'Maria Cruz');
    expect(persistedAddress?.address.notes, isEmpty);
  });

  testWidgets('address autocomplete fills fields and persists place metadata', (
    tester,
  ) async {
    SavedAddress? savedAddress;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressPage(
          onBack: () {},
          onNext: (_) {},
          autocompleteProvider: _FakeAddressAutocompleteProvider(),
          onSaveAddress: (address) async {
            savedAddress = address;
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('checkout-address-search')),
      'Mabini',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('123 Mabini Street'), findsOneWidget);

    await tester.tap(find.byKey(const Key('address-suggestion-place-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Juan Dela Cruz');
    await tester.enterText(find.byType(TextField).at(1), '09171234567');
    await _tapSaveAddress(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();

    expect(savedAddress?.address.addressLine1, '123 Mabini Street');
    expect(savedAddress?.address.barangay, 'Barangay 1');
    expect(savedAddress?.address.city, 'Quezon City');
    expect(savedAddress?.address.province, 'Metro Manila');
    expect(savedAddress?.address.postalCode, '1100');
    expect(savedAddress?.placeId, 'place-1');
    expect(savedAddress?.addressSource, 'autocomplete');
    expect(savedAddress?.latitude, 14.676);
    expect(savedAddress?.longitude, 121.0437);
  });
}

Future<void> _enterValidAddress(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'Maria Santos');
  await tester.enterText(find.byType(TextField).at(1), '09171234567');
  await tester.enterText(find.byType(TextField).at(2), '123 Mabini Street');
  await tester.enterText(find.byType(TextField).at(3), 'Metro Manila');
  await tester.enterText(find.byType(TextField).at(4), 'Quezon City');
  await tester.enterText(find.byType(TextField).at(5), 'Barangay 1');
  await tester.enterText(find.byType(TextField).at(6), '1100');
}

Future<void> _tapSaveAddress(WidgetTester tester) async {
  await tester.tap(find.text('Save to My Addresses'));
}

class _FakeAddressAutocompleteProvider implements AddressAutocompleteProvider {
  _FakeAddressAutocompleteProvider({this.addressLine1 = '123 Mabini Street'});

  final String addressLine1;

  @override
  Future<List<AddressSuggestion>> suggest({
    required String query,
    required String sessionToken,
  }) async => const [
    AddressSuggestion(
      placeId: 'place-1',
      primaryText: '123 Mabini Street',
      secondaryText: 'Quezon City, Metro Manila',
    ),
  ];

  @override
  Future<AddressPlaceDetails> details({
    required String placeId,
    required String sessionToken,
  }) async => AddressPlaceDetails(
    placeId: 'place-1',
    addressLine1: addressLine1,
    barangay: 'Barangay 1',
    city: 'Quezon City',
    province: 'Metro Manila',
    postalCode: '1100',
    latitude: 14.676,
    longitude: 121.0437,
    addressSource: 'autocomplete',
  );
}

class _FailingAddressAutocompleteProvider
    implements AddressAutocompleteProvider {
  @override
  Future<List<AddressSuggestion>> suggest({
    required String query,
    required String sessionToken,
  }) async => throw StateError('offline');

  @override
  Future<AddressPlaceDetails> details({
    required String placeId,
    required String sessionToken,
  }) async => throw StateError('offline');
}
