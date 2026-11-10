/// Application constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'Grepmind Near';
  static const String appVersion = '1.0.0';

  // API base URL. Configure via --dart-define=API_BASE_URL=http://...
  // Android Emulator's host alias reaches the Windows host, whose localhost
  // ports are forwarded to the WSL2 Docker Compose stack. Physical devices and
  // production builds should provide their reachable HTTPS URL with dart-define.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:80',
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
