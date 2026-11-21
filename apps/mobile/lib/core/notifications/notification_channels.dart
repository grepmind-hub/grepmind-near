import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android notification channel definitions for Abashyaka.
///
/// Channels are created once on app startup. Users can manage per-channel
/// settings in Android system settings. FCM messages routed through these
/// channels honor the user's channel-level preferences.
class NotificationChannels {
  NotificationChannels._();

  static const AndroidNotificationChannel verification = AndroidNotificationChannel(
    'verification',
    'Verification',
    description: 'One-time passwords and account security codes',
    importance: Importance.high,
    enableLights: true,
    enableVibration: true,
    showBadge: true,
  );

  static const AndroidNotificationChannel orders = AndroidNotificationChannel(
    'orders',
    'Orders',
    description: 'Order confirmation, preparation, pickup, and delivery updates',
    importance: Importance.high,
    enableLights: true,
    enableVibration: true,
    showBadge: true,
  );

  static const AndroidNotificationChannel deliveries = AndroidNotificationChannel(
    'deliveries',
    'Deliveries',
    description: 'Rider assignment, delivery progress, and completion alerts',
    importance: Importance.high,
    enableLights: true,
    enableVibration: true,
    showBadge: true,
  );

  static const AndroidNotificationChannel merchantOperations = AndroidNotificationChannel(
    'merchant_operations',
    'Merchant Operations',
    description: 'New orders, acceptance, and merchant workflow alerts',
    importance: Importance.high,
    enableLights: true,
    enableVibration: true,
    showBadge: true,
  );

  static const AndroidNotificationChannel riderAssignments = AndroidNotificationChannel(
    'rider_assignments',
    'Rider Assignments',
    description: 'Delivery offers, assignments, and pickup/delivery verification',
    importance: Importance.high,
    enableLights: true,
    enableVibration: true,
    showBadge: true,
  );

  static const AndroidNotificationChannel accountSecurity = AndroidNotificationChannel(
    'account_security',
    'Account Security',
    description: 'Login alerts, role changes, and security notifications',
    importance: Importance.high,
    enableLights: true,
    enableVibration: true,
    showBadge: true,
  );

  static const AndroidNotificationChannel promotions = AndroidNotificationChannel(
    'promotions',
    'Promotions',
    description: 'Offers, discounts, and promotional announcements',
    importance: Importance.low,
    enableLights: false,
    enableVibration: false,
    showBadge: false,
  );

  /// All channels in registration order.
  static final List<AndroidNotificationChannel> all = [
    verification,
    orders,
    deliveries,
    merchantOperations,
    riderAssignments,
    accountSecurity,
    promotions,
  ];

  /// Look up a channel by its id.
  static AndroidNotificationChannel? byId(String id) {
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
}
