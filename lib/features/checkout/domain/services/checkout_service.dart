import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/inventory/inventory_service.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/cart/domain/repositories/cart_repository.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';

import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/checkout/domain/services/checkout_review_provider.dart';
import 'package:scentify/features/checkout/domain/services/payment_gateway.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/orders/domain/repositories/order_repository.dart';

class CheckoutService {
  CheckoutService({
    required this.cartRepository,
    required this.catalogRepository,
    required this.inventoryService,
    required this.orderRepository,
    required this.paymentGateway,
    this.checkoutReviewProvider,
    this.cashOnDeliveryOrderProvider,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator =
           idGenerator ??
           (() => 'order-${DateTime.now().microsecondsSinceEpoch}');

  final CartRepository cartRepository;
  final CatalogRepository catalogRepository;
  final InventoryPort inventoryService;
  final OrderRepository orderRepository;
  final PaymentGateway paymentGateway;
  final CheckoutReviewProvider? checkoutReviewProvider;
  final CashOnDeliveryOrderProvider? cashOnDeliveryOrderProvider;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  Future<Order> placeOrder({
    required String userId,
    Iterable<CartItem>? selectedItems,
    required ShippingAddress shippingAddress,
    required DeliveryOption deliveryOption,
    String paymentMethod = 'gcash',
    String? addressId,
    String? orderId,
  }) async {
    if (!const {'gcash', 'maya', 'card', 'cod'}.contains(paymentMethod)) {
      throw const ValidationException('Select a supported payment method.');
    }
    final checkoutId = orderId ?? _idGenerator();

    final cart = await cartRepository.findByUserId(userId);
    if (cart == null || cart.items.isEmpty) {
      throw const ValidationException('Cannot checkout an empty cart.');
    }

    final checkoutItems = selectedItems == null
        ? cart.items
        : [
            for (final requested in selectedItems)
              cart.itemFor(requested.productId, requested.variantId) ??
                  (throw const NotFoundException(
                    'A selected cart item no longer exists.',
                  )),
          ];
    if (checkoutItems.isEmpty) {
      throw const ValidationException('Cannot checkout an empty selection.');
    }

    final quote = checkoutReviewProvider == null
        ? null
        : await checkoutReviewProvider!.createQuote(
            orderId: checkoutId,
            userId: userId,
            selectedItems: List.unmodifiable(checkoutItems),
            shippingAddress: shippingAddress,
            deliveryOption: deliveryOption,
            paymentMethod: paymentMethod,
            addressId: addressId,
          );
    if (quote != null &&
        (quote.orderId != checkoutId || quote.userId != userId)) {
      throw const AuthorizationException(
        'The reviewed order does not match this checkout.',
      );
    }

    late final List<OrderItemSnapshot> snapshots;
    late final List<InventoryRequest> inventoryRequests;
    late final ShippingAddress orderAddress;
    late final DeliveryOption orderDelivery;
    late final Money subtotal;
    late final Money total;
    if (quote == null) {
      snapshots = <OrderItemSnapshot>[];
      inventoryRequests = <InventoryRequest>[];
      for (final item in checkoutItems) {
        final product = await catalogRepository.findById(item.productId);
        if (product == null || !product.isPublished) {
          throw const NotFoundException(
            'A cart product is no longer available.',
          );
        }
        final variant = product.variantById(item.variantId);
        if (variant == null) {
          throw const NotFoundException(
            'A cart variant is no longer available.',
          );
        }
        snapshots.add(
          OrderItemSnapshot(
            productId: product.id,
            variantId: variant.id,
            productName: product.name,
            variantLabel: variant.label,
            unitPrice: variant.price,
            quantity: item.quantity,
          ),
        );
        inventoryRequests.add(
          InventoryRequest(
            productId: product.id,
            variantId: variant.id,
            quantity: item.quantity,
          ),
        );
      }
      orderAddress = shippingAddress;
      orderDelivery = deliveryOption;
      subtotal = snapshots.fold(Money(0), (sum, item) => sum + item.lineTotal);
      total = subtotal + deliveryOption.fee;
    } else {
      final requestedQuantities = {
        for (final item in checkoutItems)
          '${item.productId}|${item.variantId}': item.quantity,
      };
      final reviewedQuantities = {
        for (final item in quote.items)
          '${item.productId}|${item.variantId}': item.quantity,
      };
      if (requestedQuantities.length != checkoutItems.length ||
          reviewedQuantities.length != quote.items.length ||
          requestedQuantities.length != reviewedQuantities.length ||
          requestedQuantities.entries.any(
            (entry) => reviewedQuantities[entry.key] != entry.value,
          )) {
        throw const ValidationException(
          'The cart changed while checkout was being reviewed. Review it again.',
        );
      }
      snapshots = [
        for (final item in quote.items)
          OrderItemSnapshot(
            productId: item.productId,
            variantId: item.variantId,
            productName: item.productName,
            variantLabel: item.variantLabel,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
          ),
      ];
      inventoryRequests = [
        for (final item in quote.items)
          InventoryRequest(
            productId: item.productId,
            variantId: item.variantId,
            quantity: item.quantity,
          ),
      ];
      orderAddress = quote.shippingAddress;
      orderDelivery = quote.deliveryOption;
      subtotal = quote.subtotal;
      total = quote.total;
    }

    if (paymentMethod == 'cod') {
      final codProvider = cashOnDeliveryOrderProvider;
      if (codProvider != null) {
        final order = await codProvider.createCashOnDeliveryOrder(
          orderId: checkoutId,
          userId: userId,
          shippingAddress: orderAddress,
          deliveryOption: orderDelivery,
        );
        if (order.id != checkoutId ||
            order.userId != userId ||
            order.paymentMethod != 'cod') {
          throw const AuthorizationException(
            'The server order does not match this checkout.',
          );
        }
        return order;
      }
      final now = _clock();
      final order = Order(
        id: checkoutId,
        userId: userId,
        items: snapshots,
        shippingAddress: orderAddress,
        deliveryOption: orderDelivery,
        subtotal: subtotal,
        deliveryFee: orderDelivery.fee,
        total: total,
        status: OrderStatus.pendingConfirmation,
        paymentMethod: 'cod',
        paymentStatus: 'unpaid',
        createdAt: now,
        updatedAt: now,
      );
      var inventoryReserved = false;
      try {
        await inventoryService.reserve(inventoryRequests);
        inventoryReserved = true;
        await orderRepository.save(order);
      } catch (_) {
        try {
          final existing = await orderRepository.findById(checkoutId);
          if (existing?.userId == userId &&
              existing?.paymentMethod == 'cod' &&
              existing?.status == OrderStatus.pendingConfirmation) {
            await _consumeCartSelection(userId, cart, checkoutItems);
            return existing!;
          }
        } catch (_) {
          // Preserve the original write failure if an ambiguous save cannot be confirmed.
        }
        if (inventoryReserved) {
          await inventoryService.release(inventoryRequests);
        }
        rethrow;
      }
      await _consumeCartSelection(userId, cart, checkoutItems);
      return order;
    }

    var inventoryReserved = false;

    try {
      await inventoryService.reserve(inventoryRequests);
      inventoryReserved = true;
      final payment = await paymentGateway.createPayment(
        PaymentRequest(
          orderId: checkoutId,
          amount: total,
          paymentMethod: paymentMethod,
          supportedMethods: [paymentMethod],
          shippingAddress: {
            'fullName': orderAddress.fullName,
            'phoneNumber': orderAddress.phoneNumber,
            'addressLine1': orderAddress.addressLine1,
            'barangay': orderAddress.barangay,
            'city': orderAddress.city,
            'province': orderAddress.province,
            'postalCode': orderAddress.postalCode,
            'notes': orderAddress.notes,
          },
          deliveryOption: {
            'id': orderDelivery.id,
            'name': orderDelivery.name,
            'feeCentavos': orderDelivery.fee.centavos,
            'estimatedDays': orderDelivery.estimatedDays,
          },
        ),
      );
      if (payment.orderCreatedOnServer) {
        final order = await orderRepository.findById(checkoutId);
        if (order == null ||
            order.userId != userId ||
            order.status != OrderStatus.pendingPayment ||
            order.paymentReference != payment.reference) {
          throw const PaymentException(
            'The server could not confirm this payment order. Contact support before retrying.',
          );
        }
        return order;
      }
      final now = _clock();
      final order = Order(
        id: checkoutId,
        userId: userId,
        items: snapshots,
        shippingAddress: orderAddress,
        deliveryOption: orderDelivery,
        subtotal: subtotal,
        deliveryFee: orderDelivery.fee,
        total: total,
        status: OrderStatus.pendingPayment,
        paymentReference: payment.reference,
        paymentMethod: paymentMethod,
        paymentStatus: 'pending',
        createdAt: now,
        updatedAt: now,
      );
      await orderRepository.save(order);
      await _consumeCartSelection(userId, cart, checkoutItems);
      return order;
    } catch (_) {
      if (inventoryReserved) {
        await inventoryService.release(inventoryRequests);
      }
      rethrow;
    }
  }

  Future<void> _consumeCartSelection(
    String userId,
    Cart cart,
    List<CartItem> checkoutItems,
  ) async {
    if (checkoutItems.length == cart.items.length) {
      await cartRepository.clear(userId);
      return;
    }
    final selectedKeys = {
      for (final item in checkoutItems) '${item.productId}|${item.variantId}',
    };
    await cartRepository.save(
      cart.copyWith(
        items: cart.items
            .where(
              (item) =>
                  !selectedKeys.contains('${item.productId}|${item.variantId}'),
            )
            .toList(),
        updatedAt: _clock(),
      ),
    );
  }
}
