import 'package:cloud_functions/cloud_functions.dart';

const scentifyFunctionsRegion = 'asia-southeast1';

class MyPurchasesApi {
  MyPurchasesApi({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: scentifyFunctionsRegion);

  final FirebaseFunctions _functions;

  Future<List<MyPurchaseSummary>> fetch({
    int limit = 50,
    String? cursor,
  }) async {
    final page = await fetchPage(limit: limit, cursor: cursor);
    return page.purchases;
  }

  Future<PurchasePage> fetchPage({int limit = 50, String? cursor}) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'Use a limit from 1 to 100.');
    }
    if (cursor != null && cursor.length > 512) {
      throw ArgumentError.value(cursor, 'cursor', 'The cursor is too long.');
    }
    final data = <String, dynamic>{'limit': limit};
    if (cursor != null) data['cursor'] = cursor;
    final result = await _functions
        .httpsCallable('listMyPurchases')
        .call<Map<String, dynamic>>(data);
    final raw = result.data['purchases'];
    if (raw is! List) {
      throw const FormatException('The purchase response is invalid.');
    }
    final purchases = raw
        .whereType<Map>()
        .map(
          (value) => MyPurchaseSummary.fromMap(
            value.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
    final nextCursor = result.data['nextCursor'];
    if (nextCursor != null && nextCursor is! String) {
      throw const FormatException('The purchase cursor is invalid.');
    }
    return PurchasePage(
      purchases: purchases,
      nextCursor: nextCursor as String?,
    );
  }
}

class PurchasePage {
  const PurchasePage({required this.purchases, required this.nextCursor});

  final List<MyPurchaseSummary> purchases;
  final String? nextCursor;
}

class MyPurchaseSummary {
  MyPurchaseSummary({
    required this.id,
    required this.userId,
    required this.status,
    required this.statusLabel,
    required this.statusTimeline,
    required this.items,
    required this.shippingAddress,
    required this.deliveryOption,
    required this.subtotalCentavos,
    required this.deliveryFeeCentavos,
    required this.totalCentavos,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.paymentReference,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MyPurchaseSummary.fromMap(Map<String, dynamic> data) {
    return MyPurchaseSummary(
      id: _string(data['id'], 'id'),
      userId: _string(data['userId'], 'userId'),
      status: _string(data['status'], 'status'),
      statusLabel: _string(data['statusLabel'], 'statusLabel'),
      statusTimeline: _maps(
        data['statusTimeline'],
        'statusTimeline',
      ).map(PurchaseTimelineEntry.fromMap).toList(growable: false),
      items: _maps(
        data['items'],
        'items',
      ).map(PurchaseItemSnapshot.fromMap).toList(growable: false),
      shippingAddress: _stringMap(data['shippingAddress'], 'shippingAddress'),
      deliveryOption: _stringMap(data['deliveryOption'], 'deliveryOption'),
      subtotalCentavos: _int(data['subtotalCentavos'], 'subtotalCentavos'),
      deliveryFeeCentavos: _int(
        data['deliveryFeeCentavos'],
        'deliveryFeeCentavos',
      ),
      totalCentavos: _int(data['totalCentavos'], 'totalCentavos'),
      paymentMethod: _nullableString(data['paymentMethod']),
      paymentStatus: _string(data['paymentStatus'], 'paymentStatus'),
      paymentReference: _nullableString(data['paymentReference']),
      createdAt: _date(data['createdAt'], 'createdAt'),
      updatedAt: _date(data['updatedAt'], 'updatedAt'),
    );
  }

  final String id;
  final String userId;
  final String status;
  final String statusLabel;
  final List<PurchaseTimelineEntry> statusTimeline;
  final List<PurchaseItemSnapshot> items;
  final Map<String, String> shippingAddress;
  final Map<String, String> deliveryOption;
  final int subtotalCentavos;
  final int deliveryFeeCentavos;
  final int totalCentavos;
  final String? paymentMethod;
  final String paymentStatus;
  final String? paymentReference;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PurchaseTimelineEntry {
  const PurchaseTimelineEntry({
    required this.from,
    required this.to,
    required this.changedAt,
    required this.actorId,
  });

  factory PurchaseTimelineEntry.fromMap(Map<String, dynamic> data) {
    return PurchaseTimelineEntry(
      from: _nullableString(data['from']),
      to: _string(data['to'], 'statusTimeline.to'),
      changedAt: _date(data['changedAt'], 'statusTimeline.changedAt'),
      actorId: _string(data['actorId'], 'statusTimeline.actorId'),
    );
  }

  final String? from;
  final String to;
  final DateTime changedAt;
  final String actorId;
}

class PurchaseItemSnapshot {
  const PurchaseItemSnapshot({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.unitPriceCentavos,
    required this.quantity,
  });

  factory PurchaseItemSnapshot.fromMap(Map<String, dynamic> data) {
    return PurchaseItemSnapshot(
      productId: _string(data['productId'], 'item.productId'),
      variantId: _string(data['variantId'], 'item.variantId'),
      productName: _string(data['productName'], 'item.productName'),
      variantLabel: _string(data['variantLabel'], 'item.variantLabel'),
      unitPriceCentavos: _int(
        data['unitPriceCentavos'],
        'item.unitPriceCentavos',
      ),
      quantity: _int(data['quantity'], 'item.quantity'),
    );
  }

  final String productId;
  final String variantId;
  final String productName;
  final String variantLabel;
  final int unitPriceCentavos;
  final int quantity;
}

List<Map<String, dynamic>> _maps(Object? value, String field) {
  if (value is! List) {
    throw FormatException('Expected $field to be a list.');
  }
  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

Map<String, String> _stringMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('Expected $field to be a map.');
  }
  return value.map((key, value) {
    if (value is! String) {
      throw FormatException('Expected $field values to be strings.');
    }
    return MapEntry(key.toString(), value);
  });
}

String _string(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected $field to be a non-empty string.');
}

String? _nullableString(Object? value) =>
    value == null ? null : _string(value, 'nullable string');

int _int(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('Expected $field to be an integer.');
}

DateTime _date(Object? value, String field) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Expected $field to be an ISO timestamp.');
}
