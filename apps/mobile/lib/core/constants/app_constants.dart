/// Application constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'Grepmind Near';
  static const String appVersion = '1.0.0';

  // API base URL. Configure via --dart-define=API_BASE_URL=http://...
  // Defaults to WSL2 Docker IP (works from Android emulator on Windows).
  // For DNS "api.near.grepmind.com": add to emulator /etc/hosts (root required)
  // or use Windows port proxy + hosts file.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://172.18.160.150:80',
  );
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
  static const String activeRoleKey = 'active_role';
}
