import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/orders/domain/repositories/order_repository.dart';
import 'package:scentify/features/orders/domain/services/order_status_machine.dart';

class OrderService {
  OrderService(
    OrderRepository repository, {
    DateTime Function()? clock,
    OrderStatusMachine? statusMachine,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now,
       _statusMachine = statusMachine ?? OrderStatusMachine();

  final OrderRepository _repository;
  final DateTime Function() _clock;
  final OrderStatusMachine _statusMachine;

  Future<Order> transitionStatus({
    required String orderId,
    required OrderStatus nextStatus,
    required String actorId,
  }) async {
    if (actorId.trim().isEmpty) {
      throw const ValidationException('An order status actor is required.');
    }
    final order = await _repository.findById(orderId);
    if (order == null) {
      throw const NotFoundException('The order does not exist.');
    }
    _statusMachine.assertTransition(order.status, nextStatus);
    final now = _clock();
    final updated = order.copyWith(
      status: nextStatus,
      updatedAt: now,
      events: [
        ...order.events,
        OrderStatusEvent(
          from: order.status,
          to: nextStatus,
          changedAt: now,
          actorId: actorId,
        ),
      ],
    );
    await _repository.save(updated);
    return updated;
  }
}
