import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/notifications/notification_manager.dart';

/// Lightweight in-app notification item populated from live FCM foreground messages.
class InAppNotificationItem {
  final String title;
  final String body;
  final DateTime receivedAt;
  final bool isRead;

  const InAppNotificationItem({
    required this.title,
    required this.body,
    required this.receivedAt,
    this.isRead = false,
  });

  InAppNotificationItem copyWith({bool? isRead}) => InAppNotificationItem(
    title: title,
    body: body,
    receivedAt: receivedAt,
    isRead: isRead ?? this.isRead,
  );
}

/// Tracks foreground push notifications received during the session.
final inAppNotificationsProvider =
    StateNotifierProvider<InAppNotificationsNotifier, List<InAppNotificationItem>>(
      (ref) => InAppNotificationsNotifier(),
    );

class InAppNotificationsNotifier
    extends StateNotifier<List<InAppNotificationItem>> {
  InAppNotificationsNotifier() : super(const []);

  void addMessage(dynamic payload) {
    String title = 'Abashyaka Update';
    String body = 'You have a new notification.';
    if (payload is Map) {
      title = (payload['title'] ?? payload['notification']?['title'] ?? title)
          .toString();
      body = (payload['body'] ?? payload['notification']?['body'] ?? body)
          .toString();
    } else if (payload != null) {
      try {
        final dynamic dyn = payload;
        final notif = dyn.notification;
        if (notif != null) {
          title = (notif.title ?? title).toString();
          body = (notif.body ?? body).toString();
        }
      } catch (_) {}
    }
    state = [
      InAppNotificationItem(
        title: title,
        body: body,
        receivedAt: DateTime.now(),
      ),
      ...state,
    ].take(25).toList();
  }

  void markAllRead() {
    state = state.map((n) => n.copyWith(isRead: true)).toList();
  }
}

/// Notification state provider.
final notificationStateProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
      return NotificationNotifier(ref);
    });

/// Notifier for notification initialization state and token management.
class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier(this._ref) : super(const NotificationState()) {
    _initialize();
  }

  final Ref _ref;
  final NotificationManager _manager = NotificationManager();

  Future<void> _initialize() async {
    try {
      _manager.onMessageReceived = (payload) {
        _ref.read(inAppNotificationsProvider.notifier).addMessage(payload);
      };
      await _manager.initialize();
      final token = await _manager.getFcmToken();
      final installationId = await _manager.getInstallationId();
      state = state.copyWith(
        isInitialized: true,
        fcmToken: token,
        installationId: installationId,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isInitialized: true, error: e.toString());
    }
  }

  /// Refresh notification state after authentication changes.
  Future<void> refreshAfterAuth() async {
    await _manager.registerAfterAuth();
    final token = await _manager.getFcmToken();
    state = state.copyWith(fcmToken: token, error: null);
  }

  /// Clear notification state on logout.
  Future<void> clearOnLogout() async {
    await _manager.logoutCleanup();
    state = const NotificationState();
  }

  /// Set the OTP payload callback. Used by the OTP verification screen.
  void setOtpCallback(void Function(dynamic)? callback) {
    _manager.onOtpReceived = (payload) {
      if (callback != null) callback(payload);
    };
  }

  /// Set the general message callback.
  void setMessageCallback(void Function(dynamic)? callback) {
    _manager.onMessageReceived = (payload) {
      if (callback != null) callback(payload);
    };
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}
