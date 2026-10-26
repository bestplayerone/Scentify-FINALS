import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:scentify/features/orders/domain/models/order.dart';

const _orderNotificationChannelId = 'scentify_orders';
const _orderNotificationChannelName = 'Orders';
const _orderNotificationChannelDescription =
    'Payment and delivery updates for Scentify orders.';

class ScentifyNotification {
  const ScentifyNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.orderId,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? orderId;
}

/// Receives remote FCM messages and displays foreground notifications locally.
/// Background notification payloads are displayed by Firebase Messaging itself.
class NotificationService {
  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FlutterLocalNotificationsPlugin _localNotifications;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _tokenSubscription;
  final _notificationEvents =
      StreamController<ScentifyNotification>.broadcast();
  String? _registeredUserId;
  bool _initialized = false;

  Stream<ScentifyNotification> get notifications => _notificationEvents.stream;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      _initialized = true;
      return;
    }

    FirebaseMessaging.onBackgroundMessage(
      scentifyFirebaseMessagingBackgroundHandler,
    );

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_scentify'),
    );
    await _localNotifications.initialize(settings: initializationSettings);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _orderNotificationChannelId,
            _orderNotificationChannelName,
            description: _orderNotificationChannelDescription,
            importance: Importance.high,
          ),
        );

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showRemoteMessage(message));
    });
    _tokenSubscription = _messaging.onTokenRefresh.listen((token) {
      final userId = _registeredUserId;
      if (userId != null) {
        unawaited(_saveToken(userId, token));
      }
    });
    _initialized = true;
  }

  Future<void> registerForUser(String userId) async {
    if (kIsWeb || userId.trim().isEmpty) {
      return;
    }
    if (!_initialized) {
      await initialize();
    }
    _registeredUserId = userId;
    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _saveToken(userId, token);
    }
  }

  void clearRegisteredUser() {
    _registeredUserId = null;
  }

  Future<void> showOrderCreated(Order order) {
    final title = 'Order placed';
    final body = 'Order ${order.id} is waiting for payment confirmation.';
    _notificationEvents.add(
      ScentifyNotification(
        id: 'order-created-${order.id}',
        title: title,
        body: body,
        createdAt: DateTime.now(),
        orderId: order.id,
      ),
    );
    return _showLocalMessage(
      id: _notificationId(order.id),
      title: title,
      body: body,
      payload: order.id,
    );
  }

  Future<void> showOrderStatusChanged(Order order) {
    final title = 'Order ${_statusLabel(order.status)}';
    final body = _statusBody(order);
    _notificationEvents.add(
      ScentifyNotification(
        id: 'order-status-${order.id}-${order.status.name}',
        title: title,
        body: body,
        createdAt: DateTime.now(),
        orderId: order.id,
      ),
    );
    return _showLocalMessage(
      id: _notificationId('${order.id}-${order.status.name}'),
      title: title,
      body: body,
      payload: order.id,
    );
  }

  Future<void> _showRemoteMessage(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'Scentify';
    final body =
        notification?.body ??
        message.data['body'] ??
        'You have a new Scentify update.';
    final orderId = message.data['orderId'];
    _notificationEvents.add(
      ScentifyNotification(
        id: 'remote-${message.messageId ?? DateTime.now().microsecondsSinceEpoch}',
        title: title,
        body: body,
        createdAt: DateTime.now(),
        orderId: orderId,
      ),
    );
    return _showLocalMessage(
      id: _notificationId(
        message.messageId ?? DateTime.now().toIso8601String(),
      ),
      title: title,
      body: body,
      payload: orderId,
    );
  }

  String _statusLabel(OrderStatus status) {
    return switch (status) {
      OrderStatus.pendingPayment => 'awaiting payment review',
      OrderStatus.pendingConfirmation => 'awaiting order confirmation',
      OrderStatus.confirmed => 'confirmed',
      OrderStatus.processing => 'being prepared',
      OrderStatus.packed => 'packed',
      OrderStatus.shipped => 'on the way',
      OrderStatus.delivered => 'delivered',
      OrderStatus.cancelled => 'cancelled',
    };
  }

  String _statusBody(Order order) {
    return switch (order.status) {
      OrderStatus.pendingPayment =>
        'We are checking the payment reference for order ${order.id}.',
      OrderStatus.pendingConfirmation =>
        'We are checking the price and availability for order ${order.id}.',
      OrderStatus.confirmed =>
        'Payment confirmed. We are preparing order ${order.id}.',
      OrderStatus.processing =>
        'Our team is preparing the scents in order ${order.id}.',
      OrderStatus.packed => 'Order ${order.id} is packed and ready to ship.',
      OrderStatus.shipped => 'Order ${order.id} is on the way to you.',
      OrderStatus.delivered => 'Order ${order.id} has been delivered.',
      OrderStatus.cancelled => 'Order ${order.id} was cancelled.',
    };
  }

  Future<void> _showLocalMessage({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) {
    return _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _orderNotificationChannelId,
          _orderNotificationChannelName,
          channelDescription: _orderNotificationChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_scentify',
        ),
      ),
      payload: payload,
    );
  }

  Future<void> _saveToken(String userId, String token) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('notificationTokens')
        .doc(_tokenDocumentId(token))
        .set({
          'token': token,
          'platform': defaultTargetPlatform.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  int _notificationId(String value) => value.hashCode & 0x7fffffff;

  String _tokenDocumentId(String token) => token.replaceAll('/', '_');

  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _notificationEvents.close();
  }
}

@pragma('vm:entry-point')
Future<void> scentifyFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  if (!kIsWeb) {
    await Firebase.initializeApp();
  }
}
