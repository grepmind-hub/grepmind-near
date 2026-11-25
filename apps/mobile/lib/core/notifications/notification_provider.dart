import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/notifications/notification_manager.dart';

/// Notification state provider.
final notificationStateProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
      return NotificationNotifier();
    });

/// Notifier for notification initialization state and token management.
class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier() : super(const NotificationState()) {
    _initialize();
  }

  final NotificationManager _manager = NotificationManager();

  Future<void> _initialize() async {
    try {
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
