import 'package:cloud_functions/cloud_functions.dart';
import 'package:scentify/core/orders/my_purchases_api.dart';

abstract interface class AddressAutocompleteProvider {
  Future<List<AddressSuggestion>> suggest({
    required String query,
    required String sessionToken,
  });

  Future<AddressPlaceDetails> details({
    required String placeId,
    required String sessionToken,
  });
}

class AddressAutocompleteApi implements AddressAutocompleteProvider {
  AddressAutocompleteApi({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: scentifyFunctionsRegion);

  final FirebaseFunctions _functions;

  @override
  Future<List<AddressSuggestion>> suggest({
    required String query,
    required String sessionToken,
  }) async {
    final result = await _functions
        .httpsCallable('addressAutocomplete')
        .call<List<dynamic>>({'query': query, 'sessionToken': sessionToken});
    final raw = result.data;
    return raw
        .whereType<Map>()
        .map(
          (value) => AddressSuggestion.fromMap(
            value.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<AddressPlaceDetails> details({
    required String placeId,
    required String sessionToken,
  }) async {
    final result = await _functions
        .httpsCallable('addressPlaceDetails')
        .call<Map<String, dynamic>>({
          'placeId': placeId,
          'sessionToken': sessionToken,
        });
    return AddressPlaceDetails.fromMap(result.data);
  }
}

class AddressSuggestion {
  const AddressSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  factory AddressSuggestion.fromMap(Map<String, dynamic> data) {
    final placeId = data['placeId'];
    final primaryText = data['primaryText'];
    final secondaryText = data['secondaryText'];
    if (placeId is! String ||
        primaryText is! String ||
        secondaryText is! String) {
      throw const FormatException(
        'The address suggestion response is invalid.',
      );
    }
    return AddressSuggestion(
      placeId: placeId,
      primaryText: primaryText,
      secondaryText: secondaryText,
    );
  }

  final String placeId;
  final String primaryText;
  final String secondaryText;
}

class AddressPlaceDetails {
  const AddressPlaceDetails({
    required this.placeId,
    required this.addressLine1,
    required this.barangay,
    required this.city,
    required this.province,
    required this.postalCode,
    required this.latitude,
    required this.longitude,
    required this.addressSource,
  });

  factory AddressPlaceDetails.fromMap(Map<String, dynamic> data) {
    final values = [
      data['placeId'],
      data['addressLine1'],
      data['barangay'],
      data['city'],
      data['province'],
      data['postalCode'],
      data['latitude'],
      data['longitude'],
      data['addressSource'],
    ];
    if (values[0] is! String ||
        values[1] is! String ||
        values[2] is! String ||
        values[3] is! String ||
        values[4] is! String ||
        values[5] is! String ||
        values[6] is! num ||
        values[7] is! num ||
        values[8] != 'autocomplete') {
      throw const FormatException('The address details response is invalid.');
    }
    return AddressPlaceDetails(
      placeId: values[0] as String,
      addressLine1: values[1] as String,
      barangay: values[2] as String,
      city: values[3] as String,
      province: values[4] as String,
      postalCode: values[5] as String,
      latitude: (values[6] as num).toDouble(),
      longitude: (values[7] as num).toDouble(),
      addressSource: values[8] as String,
    );
  }

  final String placeId;
  final String addressLine1;
  final String barangay;
  final String city;
  final String province;
  final String postalCode;
  final double latitude;
  final double longitude;
  final String addressSource;
}
