import 'package:scentify/core/errors/app_exception.dart';

/// Philippine currency represented in centavos to avoid floating-point totals.
class Money implements Comparable<Money> {
  Money(int centavos) : centavos = _validate(centavos);

  final int centavos;

  static int _validate(int centavos) {
    if (centavos < 0) {
      throw const ValidationException('Money cannot be negative.');
    }
    return centavos;
  }

  Money operator +(Money other) => Money(centavos + other.centavos);

  Money operator -(Money other) {
    if (other.centavos > centavos) {
      throw const ValidationException('Money cannot become negative.');
    }
    return Money(centavos - other.centavos);
  }

  Money operator *(int multiplier) {
    if (multiplier < 0) {
      throw const ValidationException(
        'Money cannot use a negative multiplier.',
      );
    }
    return Money(centavos * multiplier);
  }

  @override
  int compareTo(Money other) => centavos.compareTo(other.centavos);

  bool operator <(Money other) => centavos < other.centavos;

  bool operator <=(Money other) => centavos <= other.centavos;

  bool operator >(Money other) => centavos > other.centavos;

  bool operator >=(Money other) => centavos >= other.centavos;

  @override
  bool operator ==(Object other) =>
      other is Money && other.centavos == centavos;

  @override
  int get hashCode => centavos.hashCode;

  @override
  String toString() {
    final pesos = centavos ~/ 100;
    final remainder = (centavos % 100).toString().padLeft(2, '0');
    return '₱$pesos.$remainder';
  }
}
