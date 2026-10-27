/// Application constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'Grepmind Near';
  static const String appVersion = '1.0.0';

  // API base URL. Emulator reaches host via 10.0.2.2.
  static const String apiBaseUrl = 'http://10.0.2.2:8080';
  static const String apiVersion = '/api/v1';

  // Request timeout (seconds).
  static const Duration requestTimeout = Duration(seconds: 30);

  // Pagination defaults.
  static const int defaultLimit = 20;
  static const int maxLimit = 50;

  // Search debounce (ms).
  static const int searchDebounceMs = 400;

  // Category slugs.
  static const List<String> categorySlugs = [
    'grocery',
    'hardware',
    'medical',
    'restaurant',
    'salon',
    'plumber',
    'electrician',
    'carpenter',
    'tailor',
    'general',
  ];

  // Secure storage keys.
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey = 'user';
  static const String selectedLocationKey = 'selected_location';
}
