import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

enum NotificationPermissionState { allowed, notRequested, denied, unavailable }

/// The platform and persistence boundary can be replaced in tests.
abstract class NotificationPermissionGateway {
  Future<bool?> isEnabled();
  Future<bool?> request();
  Future<bool> wasRequested();
  Future<void> markRequested();
  Future<bool> openSettings();
}

class AndroidNotificationPermissionGateway
    implements NotificationPermissionGateway {
  AndroidFlutterLocalNotificationsPlugin? get _android =>
      FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _requestedKey = 'notification_permission_requested';

  bool get _supported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _android != null;

  @override
  Future<bool?> isEnabled() =>
      _supported ? _android!.areNotificationsEnabled() : Future.value(null);

  @override
  Future<bool?> request() => _supported
      ? _android!.requestNotificationsPermission()
      : Future.value(null);

  @override
  Future<bool> wasRequested() async =>
      await _storage.read(key: _requestedKey) == 'true';

  @override
  Future<void> markRequested() =>
      _storage.write(key: _requestedKey, value: 'true');

  @override
  Future<bool> openSettings() => Geolocator.openAppSettings();
}

class NotificationPermissionManager {
  NotificationPermissionManager(this._gateway);
  final NotificationPermissionGateway _gateway;

  Future<NotificationPermissionState> status() async {
    try {
      final enabled = await _gateway.isEnabled();
      if (enabled == null) return NotificationPermissionState.unavailable;
      if (enabled) return NotificationPermissionState.allowed;
      return await _gateway.wasRequested()
          ? NotificationPermissionState.denied
          : NotificationPermissionState.notRequested;
    } catch (_) {
      return NotificationPermissionState.unavailable;
    }
  }

  /// The caller must explain why notifications are useful before invoking this.
  Future<NotificationPermissionState> requestOnce() async {
    final current = await status();
    if (current != NotificationPermissionState.notRequested) return current;
    try {
      await _gateway.markRequested();
      await _gateway.request();
      return await status();
    } catch (_) {
      return NotificationPermissionState.unavailable;
    }
  }

  Future<bool> openSettings() async {
    try {
      return await _gateway.openSettings();
    } catch (_) {
      return false;
    }
  }
}
