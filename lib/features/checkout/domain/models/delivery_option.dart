import 'package:scentify/core/models/money.dart';

class DeliveryOption {
  DeliveryOption({
    required this.id,
    required this.name,
    required this.fee,
    required this.estimatedDays,
  });

  final String id;
  final String name;
  final Money fee;
  final String estimatedDays;
}
