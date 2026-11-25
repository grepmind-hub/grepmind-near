import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grepmind_mobile/core/constants/app_constants.dart';
import 'package:grepmind_mobile/core/notifications/notification_channels.dart';
import 'package:grepmind_mobile/core/notifications/notification_permission.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

/// Payload of an FCM data message carrying an OTP code for test delivery.
/// Data-only messages do not display on the lock screen; the app renders
/// the OTP banner UI from the payload.
class FcmOtpPayload {
  final String otpCode;
  final String challengeId;
  final String phoneE164;
  final DateTime expiresAt;
  final String runId;
  final String channel;

  FcmOtpPayload({
    required this.otpCode,
    required this.challengeId,
    required this.phoneE164,
    required this.expiresAt,
    required this.runId,
    this.channel = 'verification',
  });

  factory FcmOtpPayload.fromMap(Map<String, dynamic> map) {
    return FcmOtpPayload(
      otpCode: map['otp_code'] as String? ?? '',
      challengeId: map['challenge_id'] as String? ?? '',
      phoneE164: map['phone_e164'] as String? ?? '',
      expiresAt: _parseTime(map['expires_at']),
      runId: map['run_id'] as String? ?? '',
      channel: map['channel'] as String? ?? 'verification',
    );
  }

  static DateTime _parseTime(dynamic value) {
    if (value == null)
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
  }

  bool matchesChallenge(
    String? expectedChallenge,
    String expectedPhone,
    DateTime now,
  ) =>
      expectedChallenge != null &&
      expectedChallenge.isNotEmpty &&
      challengeId == expectedChallenge &&
      phoneE164 == expectedPhone &&
      RegExp(r'^\d{6}$').hasMatch(otpCode) &&
      expiresAt.isAfter(now);
}

/// General FCM message payload.
class FcmMessagePayload {
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;

  FcmMessagePayload({
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
  });

  factory FcmMessagePayload.fromMap(Map<String, dynamic> map) {
    return FcmMessagePayload(
      type: map['type'] as String? ?? 'notification',
      title: map['title'] as String? ?? 'Abashyaka',
      body: map['body'] as String? ?? '',
      data: Map<String, dynamic>.from(map['data'] ?? const {}),
    );
  }
}

/// State of notification initialization and token management.
class NotificationState {
  final bool isInitialized;
  final bool permissionGranted;
  final String? fcmToken;
  final String? installationId;
  final String? error;

  const NotificationState({
    this.isInitialized = false,
    this.permissionGranted = false,
    this.fcmToken,
    this.installationId,
    this.error,
  });

  NotificationState copyWith({
    bool? isInitialized,
    bool? permissionGranted,
    String? fcmToken,
    String? installationId,
    String? error,
    bool clearError = false,
  }) {
    return NotificationState(
      isInitialized: isInitialized ?? this.isInitialized,
      permissionGranted: permissionGranted ?? this.permissionGranted,
      fcmToken: fcmToken ?? this.fcmToken,
      installationId: installationId ?? this.installationId,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Centralized notification manager for Firebase Cloud Messaging.
///
/// Handles FCM initialization, Android 13+ permission, token registration,
/// token refresh, foreground/background/terminated message handling, and
/// association of installations with authenticated users.
class NotificationManager {
  NotificationManager._();

  static final NotificationManager _instance = NotificationManager._();
  factory NotificationManager() => _instance;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiClient _api = ApiClient();

  static const _fcmTokenKey = 'fcm_token';
  static const _installationIdKey = 'installation_id';
  static const _notificationSetupKey = 'notification_channels_setup';
  static const int _otpNotificationId = 4100;

  StreamSubscription? _tokenSubscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _notificationResponseSubscription;

  /// Callback for incoming OTP payloads. Set by the OTP verification screen.
  void Function(FcmOtpPayload)? onOtpReceived;

  /// Callback for general notification messages. Set by the notification UI.
  void Function(FcmMessagePayload)? onMessageReceived;

  /// Initialize Firebase Messaging and local notifications.
  /// Must be called after Firebase is initialized.
  Future<void> initialize() async {
    try {
      await _createNotificationChannels();

      // Request Android 13+ notification permission via flutter_local_notifications
      // (more reliable than firebase_messaging on Android).
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      bool granted = true;
      if (androidPlugin != null) {
        final result = await androidPlugin.requestNotificationsPermission();
        granted = result ?? false;
      }

      if (kDebugMode) {
        debugPrint('Notification permission granted: $granted');
      }

      // Get the FCM token.
      final token = await _messaging.getToken();
      if (token != null) {
        await _storage.write(key: _fcmTokenKey, value: token);
      }

      // Generate or load installation ID.
      final existingInstallation = await _storage.read(key: _installationIdKey);
      String installationId;
      if (existingInstallation != null && existingInstallation.isNotEmpty) {
        installationId = existingInstallation;
      } else {
        installationId = _generateInstallationId();
        await _storage.write(key: _installationIdKey, value: installationId);
      }

      // Register token refresh listener.
      _tokenSubscription = _messaging.onTokenRefresh.listen((newToken) async {
        await _storage.write(key: _fcmTokenKey, value: newToken);
        await _registerDeviceIfAuthenticated(newToken, installationId);
      });

      // Listen to foreground messages.
      _messageSubscription = FirebaseMessaging.onMessage.listen((
        RemoteMessage message,
      ) async {
        await _handleIncomingMessage(message);
      });

      // Listen to notification taps (app in background).
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleMessageTap(message);
      });

      // Handle terminated app launch (app opened from terminated state via notification).
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageTap(initialMessage);
      }

      // Register device with backend if already authenticated.
      await _registerDeviceIfAuthenticated(token ?? '', installationId);

      if (kDebugMode) {
        debugPrint(
          'NotificationManager initialized: token=${token != null}, installation=$installationId',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NotificationManager initialization error: $e');
      }
      // Initialization failure must not block app startup.
    }
  }

  /// Create Android notification channels.
  Future<void> _createNotificationChannels() async {
    const setupKey = _notificationSetupKey;
    final alreadySetup = await _storage.read(key: setupKey) == 'true';
    if (alreadySetup) return;

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;

    for (final channel in NotificationChannels.all) {
      await androidPlugin.createNotificationChannel(channel);
    }

    await _storage.write(key: setupKey, value: 'true');
  }

  String _generateInstallationId() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  /// Handle an incoming FCM message while the app is in the foreground.
  Future<void> _handleIncomingMessage(RemoteMessage message) async {
    final data = message.data;
    if (data.isEmpty) return;

    final type = data['type'] as String? ?? '';

    if (type == 'otp') {
      final payload = FcmOtpPayload.fromMap(data);
      if (payload.otpCode.isEmpty ||
          payload.expiresAt.isBefore(DateTime.now())) {
        return;
      }
      // Surface the code immediately as a heads-up system notification while
      // the app is foregrounded, so the user does not have to find an in-app
      // banner. The lock screen shows only the generic public version.
      await _showOtpNotification(payload);
      if (onOtpReceived != null) {
        onOtpReceived!(payload);
      }
      return;
    }

    final payload = FcmMessagePayload(
      type: type,
      title:
          data['title'] as String? ??
          message.notification?.title ??
          'Abashyaka',
      body: data['body'] as String? ?? message.notification?.body ?? '',
      data: Map<String, dynamic>.from(data),
    );
    if (onMessageReceived != null) {
      onMessageReceived!(payload);
    }

    // Show a local notification so the message is visible even when the app
    // is foregrounded.
    _showLocalNotification(payload.title, payload.body, payload.data);
  }

  /// Show the OTP code as a heads-up notification at the top of the screen.
  Future<void> _showOtpNotification(FcmOtpPayload payload) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'verification',
        'Verification',
        channelDescription: 'One-time passwords and account security codes',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.private,
      );
      const platformDetails = NotificationDetails(android: androidDetails);
      await _localNotifications.show(
        id: _otpNotificationId,
        title: 'Abashyaka verification code',
        body:
            'Your Abashyaka one-time code is ${payload.otpCode}. '
            'It expires at ${payload.expiresAt.toLocal().toString().substring(11, 16)}.',
        notificationDetails: platformDetails,
        payload: jsonEncode(<String, String>{
          'type': 'otp',
          'challenge_id': payload.challengeId,
        }),
      );
    } catch (_) {
      // Notification display failure must not block login.
    }
  }

  /// Handle a notification tap (app opened from background/terminated).
  void _handleMessageTap(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;
    final type = data['type'] as String? ?? '';
    if (type == 'otp' && onOtpReceived != null) {
      final payload = FcmOtpPayload.fromMap(data);
      if (!payload.expiresAt.isBefore(DateTime.now())) {
        onOtpReceived!(payload);
      }
    }
    if (onMessageReceived != null) {
      onMessageReceived!(FcmMessagePayload.fromMap(data));
    }
  }

  /// Show a local notification for a foregrounded message.
  Future<void> _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> payload,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'orders',
      'Orders',
      channelDescription: 'Order and delivery updates',
      importance: Importance.high,
      priority: Priority.high,
    );
    const platformDetails = NotificationDetails(android: androidDetails);
    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: jsonEncode(payload),
    );
  }

  /// Register the device installation with the backend.
  /// Called when the user is authenticated or when the token changes.
  Future<void> _registerDeviceIfAuthenticated(
    String token,
    String installationId,
  ) async {
    if (token.isEmpty) return;
    final storage = const FlutterSecureStorage();
    final accessToken = await storage.read(key: AppConstants.accessTokenKey);
    if (accessToken == null || accessToken.isEmpty) return;

    final permissionState = await NotificationPermissionManager(
      AndroidNotificationPermissionGateway(),
    ).status();
    final granted = permissionState == NotificationPermissionState.allowed;

    try {
      await _api.post(
        '/devices/register',
        data: {
          'installation_id': installationId,
          'fcm_token': token,
          'platform': 'android',
          'environment': const String.fromEnvironment(
            'FIREBASE_ENVIRONMENT',
            defaultValue: 'qa',
          ),
          'notification_permission': granted,
        },
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } catch (_) {
      // Registration failure must not block app operation.
    }
  }

  /// Get the stored FCM token.
  Future<String?> getFcmToken() async {
    return await _storage.read(key: _fcmTokenKey);
  }

  /// Get the stored installation ID.
  Future<String?> getInstallationId() async {
    return await _storage.read(key: _installationIdKey);
  }

  /// Register the device after successful authentication.
  /// Associates the pre-login installation with the authenticated user.
  Future<void> registerAfterAuth() async {
    final token = await getFcmToken();
    final installationId = await getInstallationId();
    if (token == null || installationId == null) return;
    await _registerDeviceIfAuthenticated(token, installationId);
  }

  /// Revoke all device registrations on logout.
  Future<void> logoutCleanup() async {
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _notificationResponseSubscription?.cancel();

    final storage = const FlutterSecureStorage();
    final accessToken = await storage.read(key: AppConstants.accessTokenKey);
    if (accessToken == null || accessToken.isEmpty) return;

    final installationId = await getInstallationId();
    final fcmToken = await getFcmToken();

    try {
      await _api.post(
        '/devices/revoke',
        data: {
          if (installationId != null) 'installation_id': installationId,
          if (fcmToken != null) 'fcm_token': fcmToken,
        },
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } catch (_) {
      // Revocation failure must not block logout.
    }

    await storage.delete(key: _fcmTokenKey);
    // Keep the installation ID so re-login can re-associate it.
  }

  /// Dispose all subscriptions. Call on app teardown.
  void dispose() {
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _notificationResponseSubscription?.cancel();
  }
}
