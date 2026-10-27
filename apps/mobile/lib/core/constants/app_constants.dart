/// Application constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'Grepmind Near';
  static const String appVersion = '1.0.0';

  // API base URL. Android emulator on Windows reaches WSL2 Docker API via WSL2 IP.
  // To use DNS "api.near.grepmind.com" instead, add `172.18.160.150 api.near.grepmind.com`
  // to the emulator's /etc/hosts (requires rooted emulator) or your local hosts file.
  static const String apiBaseUrl = 'http://172.18.160.150:80';
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
