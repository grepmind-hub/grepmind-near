import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/constants/app_constants.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/notifications/notification_manager.dart';

const bool _qaOtpAutomation = bool.fromEnvironment(
  'QA_OTP_AUTOMATION',
  defaultValue: true,
);

/// Authentication state.
class AuthState {
  final AppUser? user;
  final String? accessToken;
  final bool isLoading;
  final bool isAuthenticated;
  final String? activeRole; // customer, merchant, rider, or admin

  const AuthState({
    this.user,
    this.accessToken,
    this.isLoading = false,
    this.activeRole,
  }) : isAuthenticated = user != null;

  AuthState copyWith({
    AppUser? user,
    String? accessToken,
    bool? isLoading,
    String? activeRole,
    bool clearActiveRole = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      isLoading: isLoading ?? this.isLoading,
      activeRole: clearActiveRole ? null : (activeRole ?? this.activeRole),
    );
  }
}

/// Auth notifier backed by Riverpod and secure storage.
class AuthNotifier extends StateNotifier<AuthState> {
  String? _lastOtpError;
  String? get lastOtpError => _lastOtpError;

  AuthNotifier() : this._(restoreSession: true);

  @visibleForTesting
  AuthNotifier.forTesting() : this._(restoreSession: false);

  AuthNotifier._({required bool restoreSession}) : super(const AuthState()) {
    if (restoreSession) _loadSession();
  }

  Future<void> _loadSession() async {
    state = state.copyWith(isLoading: true);
    final storage = const FlutterSecureStorage();
    final token = await storage.read(key: AppConstants.accessTokenKey);
    final userJson = await storage.read(key: AppConstants.userKey);
    final savedRole = await storage.read(key: AppConstants.activeRoleKey);
    if (token != null && userJson != null) {
      try {
        final cachedUser = AppUser.fromJson(
          jsonDecode(userJson) as Map<String, dynamic>,
        );
        state = state.copyWith(
          user: cachedUser,
          accessToken: token,
          isLoading: true,
        );

        // A saved workspace is only a preference. Re-read current roles from
        // the API before restoring privileged merchant, rider, or admin mode.
        try {
          final response = await apiClient.get('/me');
          final data =
              (response.data as Map<String, dynamic>)['data']
                  as Map<String, dynamic>;
          final verifiedUser = AppUser.fromJson(data);
          final restoredRole =
              savedRole != null && _userCanUseRole(verifiedUser, savedRole)
              ? savedRole
              : null;
          await storage.write(
            key: AppConstants.userKey,
            value: jsonEncode(verifiedUser.toJson()),
          );
          if (restoredRole == null && savedRole != null) {
            await storage.delete(key: AppConstants.activeRoleKey);
          }
          state = state.copyWith(
            user: verifiedUser,
            activeRole: restoredRole,
            clearActiveRole: restoredRole == null,
            isLoading: false,
          );
        } catch (_) {
          // Offline fallback is customer-only. Never restore a cached
          // merchant, rider, or admin role without a fresh backend check.
          final allowCustomerFallback =
              savedRole == 'customer' && cachedUser.roles.contains('customer');
          if (!allowCustomerFallback && savedRole != null) {
            await storage.delete(key: AppConstants.activeRoleKey);
          }
          state = state.copyWith(
            user: cachedUser,
            activeRole: allowCustomerFallback ? 'customer' : null,
            clearActiveRole: !allowCustomerFallback,
            isLoading: false,
          );
        }
      } catch (_) {
        state = state.copyWith(isLoading: false);
      }
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<AppUser?> refreshCurrentUser() async {
    if (!state.isAuthenticated) return null;
    try {
      final response = await apiClient.get('/me');
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final user = AppUser.fromJson(data);
      await const FlutterSecureStorage().write(
        key: AppConstants.userKey,
        value: jsonEncode(user.toJson()),
      );
      state = state.copyWith(user: user);
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<bool> setActiveRole(String role) async {
    if (!const {'customer', 'merchant', 'rider', 'admin'}.contains(role)) {
      return false;
    }
    final user = await refreshCurrentUser();
    if (user == null || !_userCanUseRole(user, role)) return false;

    final storage = const FlutterSecureStorage();
    await storage.write(key: AppConstants.activeRoleKey, value: role);
    state = state.copyWith(activeRole: role);
    return true;
  }

  bool _userCanUseRole(AppUser user, String role) {
    switch (role) {
      case 'customer':
        return user.roles.contains('customer');
      case 'merchant':
        return user.roles.contains('merchant') ||
            user.roles.contains('professional');
      case 'rider':
        return user.roles.contains('rider') && user.riderStatus == 'approved';
      case 'admin':
        return user.roles.contains(role);
      default:
        return false;
    }
  }

  Future<void> clearActiveRole() async {
    final storage = const FlutterSecureStorage();
    await storage.delete(key: AppConstants.activeRoleKey);
    state = state.copyWith(clearActiveRole: true);
  }

  Future<void> setSession({
    required String token,
    required AppUser user,
    String? activeRole,
  }) async {
    final storage = const FlutterSecureStorage();
    await storage.write(key: AppConstants.accessTokenKey, value: token);
    await storage.write(
      key: AppConstants.userKey,
      value: jsonEncode(user.toJson()),
    );
    if (activeRole != null) {
      await storage.write(key: AppConstants.activeRoleKey, value: activeRole);
    }
    state = state.copyWith(
      user: user,
      accessToken: token,
      activeRole: activeRole,
      isLoading: false,
    );
  }

  Future<bool> updateProfile(Map<String, dynamic> changes) async {
    try {
      final response = await apiClient.patch('/me', data: changes);
      final envelope = response.data as Map<String, dynamic>;
      final data = envelope['data'] as Map<String, dynamic>;
      final updatedUser = AppUser.fromJson(data);
      await setSession(
        token: state.accessToken ?? '',
        user: updatedUser,
        activeRole: state.activeRole,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    final storage = const FlutterSecureStorage();
    try {
      await apiClient.post('/auth/logout');
    } catch (_) {
      // Local credentials are always cleared, including when offline.
    }
    await storage.delete(key: AppConstants.accessTokenKey);
    await storage.delete(key: AppConstants.refreshTokenKey);
    await storage.delete(key: AppConstants.userKey);
    await storage.delete(key: AppConstants.activeRoleKey);
    // Clean up device registration on logout (Phase F3).
    await NotificationManager().logoutCleanup();
    state = const AuthState();
  }

  /// Requests a server-generated OTP challenge. The response never contains
  /// the code; delivery is handled by the configured SMS/QA transport.
  Future<Map<String, dynamic>?> requestOTP(String phone) async {
    // Get installation ID for pre-login device registration.
    String? installationId;
    if (const bool.fromEnvironment('FCM_TEST_OTP_ENABLED')) {
      try {
        installationId = await NotificationManager().getInstallationId();
      } catch (_) {
        // Existing SMS and private QA transports do not depend on FCM storage.
      }
    }
    try {
      final res = await apiClient.post(
        '/auth/otp/request',
        data: {
          'phone_e164': phone,
          if (installationId != null) 'installation_id': installationId,
        },
      );
      final data = res.data as Map<String, dynamic>;
      final resultData = data['data'] as Map<String, dynamic>;
      final challengeId = resultData['challenge_id'];
      final expiresAt = resultData['expires_at'];
      if (kDebugMode &&
          _qaOtpAutomation &&
          challengeId is String &&
          expiresAt is String) {
        // QA test-runner instrumentation exposes challenge metadata only.
        // The OTP remains exclusively in the private, single-use QA reader.
        final challengeMetadata = jsonEncode(<String, String>{
          'challenge_id': challengeId,
          'expires_at': expiresAt,
        });
        debugPrint('QA_OTP_CHALLENGE $challengeMetadata');
      }
      _lastOtpError = null;
      return {
        'phone_e164': resultData['phone_e164'],
        'challenge_id': challengeId,
        'expires_at': expiresAt,
        'status': resultData['status'],
      };
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 429) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> && data['error'] != null) {
          final errMap = data['error'];
          if (errMap is Map<String, dynamic> && errMap['message'] != null) {
            _lastOtpError = errMap['message'] as String;
          } else {
            _lastOtpError =
                'OTP request limit reached. Please wait a few minutes before trying again.';
          }
        } else {
          _lastOtpError =
              'OTP request limit reached. Please wait a few minutes before trying again.';
        }
      } else {
        _lastOtpError = null;
      }
      return null;
    }
  }

  /// Verify an OTP and establish a session.
  Future<bool> verifyOTP(
    String phone,
    String otpCode, {
    String? challengeId,
    String? preferredRole,
  }) async {
    try {
      final res = await apiClient.post(
        '/auth/otp/verify',
        data: {
          'phone_e164': phone,
          'otp_code': otpCode,
          ...?(challengeId == null ? null : {'challenge_id': challengeId}),
        },
      );
      final data = res.data as Map<String, dynamic>;
      final resultData = data['data'] as Map<String, dynamic>;
      final accessToken = resultData['access_token'] as String;
      final refreshToken = resultData['refresh_token'] as String;
      final userMap = resultData['user'] as Map<String, dynamic>;
      final user = AppUser.fromJson(userMap);
      final targetRole =
          preferredRole != null &&
              (preferredRole == 'merchant'
                  ? (user.roles.contains('merchant') ||
                        user.roles.contains('professional'))
                  : user.roles.contains(preferredRole))
          ? preferredRole
          : (user.roles.contains('merchant') && !user.roles.contains('customer')
                ? 'merchant'
                : null);
      await setSession(token: accessToken, user: user, activeRole: targetRole);
      await _storeRefreshToken(refreshToken);
      await NotificationManager().registerAfterAuth();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _storeRefreshToken(String token) async {
    final storage = const FlutterSecureStorage();
    await storage.write(key: AppConstants.refreshTokenKey, value: token);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authProvider).user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

/// Location model for multi-city discovery and expansion.
class AppLocation {
  final String cityName;
  final String localityName;
  final String localityId;
  final double latitude;
  final double longitude;
  final bool isSupported;
  final int activeBusinessCount;

  const AppLocation({
    required this.cityName,
    this.localityName = '',
    this.localityId = '',
    required this.latitude,
    required this.longitude,
    this.isSupported = true,
    this.activeBusinessCount = 0,
  });

  String get displayName =>
      localityName.isNotEmpty ? '$localityName, $cityName' : cityName;

  AppLocation copyWith({
    String? cityName,
    String? localityName,
    String? localityId,
    double? latitude,
    double? longitude,
    bool? isSupported,
    int? activeBusinessCount,
  }) {
    return AppLocation(
      cityName: cityName ?? this.cityName,
      localityName: localityName ?? this.localityName,
      localityId: localityId ?? this.localityId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isSupported: isSupported ?? this.isSupported,
      activeBusinessCount: activeBusinessCount ?? this.activeBusinessCount,
    );
  }
}

class LocationNotifier extends StateNotifier<AppLocation> {
  LocationNotifier()
    : super(const AppLocation(cityName: '', latitude: 0, longitude: 0));
  Future<void>? _defaultLocationLoad;

  Future<void> loadDefaultLocation() {
    if (state.cityName.isNotEmpty) return Future<void>.value();
    return _defaultLocationLoad ??= _fetchDefaultLocation().whenComplete(() {
      _defaultLocationLoad = null;
    });
  }

  Future<void> _fetchDefaultLocation() async {
    try {
      final response = await apiClient.get('/locations');
      final data = response.data as Map<String, dynamic>;
      final locations = data['data'] as List<dynamic>? ?? const [];
      if (locations.isEmpty || state.cityName.isNotEmpty) return;

      final location = locations.first as Map<String, dynamic>;
      final localityName = location['locality'] as String? ?? '';
      final canonicalLocalityId = localityName.toLowerCase() == 'chhatia'
          ? '02200000-0000-4000-8000-000000000201'
          : localityName.toLowerCase() == 'kuanpal'
          ? '02200000-0000-4000-8000-000000000101'
          : (location['locality_id'] as String? ?? '');
      setLocation(
        AppLocation(
          cityName: location['city'] as String,
          localityName: localityName,
          localityId: canonicalLocalityId,
          latitude: (location['latitude'] as num).toDouble(),
          longitude: (location['longitude'] as num).toDouble(),
          activeBusinessCount: (location['count'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (_) {
      // Keep discovery usable; the location picker can retry explicitly.
    }
  }

  void setLocation(AppLocation loc) {
    state = loc;
  }
}

final appLocationProvider =
    StateNotifierProvider<LocationNotifier, AppLocation>((ref) {
      return LocationNotifier();
    });

/// Businesses discovery state.
class BusinessesState {
  final List<Business> items;
  final bool isLoading;
  final bool hasMore;
  final String? cursor;
  final String? error;
  final String? query;

  const BusinessesState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.cursor,
    this.error,
    this.query,
  });

  BusinessesState copyWith({
    List<Business>? items,
    bool? isLoading,
    bool? hasMore,
    String? cursor,
    String? error,
    String? query,
    bool reset = false,
  }) {
    return BusinessesState(
      items: reset ? (items ?? const []) : (items ?? this.items),
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      cursor: cursor ?? this.cursor,
      error: error ?? this.error,
      query: query ?? this.query,
    );
  }
}

/// Business discovery notifier backed by real API calls.
class BusinessesNotifier extends StateNotifier<BusinessesState> {
  BusinessesNotifier() : super(const BusinessesState());
  int _requestSequence = 0;

  Future<void> search({
    required String query,
    double? lat,
    double? lng,
    int? radiusM,
    String? categorySlug,
    String? city,
    bool? openNow,
    bool? availableNow,
    String sort = 'relevance',
    bool reset = true,
  }) async {
    final requestSequence = ++_requestSequence;
    if (reset) {
      state = BusinessesState(query: query, isLoading: true);
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final res = await apiClient.get(
        '/businesses',
        queryParameters: {
          'q': query,
          'lat': lat,
          'lng': lng,
          'radius_m': radiusM ?? 5000,
          'category_slug': categorySlug,
          'city': city,
          'open_now': openNow,
          'available_now': availableNow,
          'sort': sort,
          'limit': AppConstants.defaultLimit,
          'cursor': state.cursor,
        },
      );

      if (!mounted || requestSequence != _requestSequence) return;

      final data = res.data as Map<String, dynamic>;
      final items =
          (data['data'] as List<dynamic>?)
              ?.map((e) => Business.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
      final meta = data['meta'] as Map<String, dynamic>?;

      state = state.copyWith(
        items: reset ? items : [...state.items, ...items],
        isLoading: false,
        cursor: meta?['next_cursor'] as String?,
        hasMore: items.length >= AppConstants.defaultLimit,
      );
    } catch (e) {
      if (!mounted || requestSequence != _requestSequence) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> nearby({
    required double lat,
    required double lng,
    int radiusM = 5000,
    String? city,
    String? categorySlug,
    bool reset = true,
  }) async {
    final requestSequence = ++_requestSequence;
    if (reset) {
      state = const BusinessesState(isLoading: true);
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final res = await apiClient.get(
        '/nearby',
        queryParameters: {
          'city': city,
          'category_slug': categorySlug,
          'lat': lat,
          'lng': lng,
          'radius_m': radiusM,
          'limit': 50,
          'cursor': state.cursor,
        },
      );

      final data = res.data as Map<String, dynamic>;
      if (!mounted || requestSequence != _requestSequence) return;
      final items =
          (data['data'] as List<dynamic>?)
              ?.map((e) => Business.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
      final meta = data['meta'] as Map<String, dynamic>?;

      state = state.copyWith(
        items: reset ? items : [...state.items, ...items],
        isLoading: false,
        cursor: meta?['next_cursor'] as String?,
        hasMore: items.length >= AppConstants.defaultLimit,
      );
    } catch (e) {
      if (!mounted || requestSequence != _requestSequence) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<BusinessDetail?> detail(String id) async {
    try {
      final res = await apiClient.get('/businesses/$id');
      final data = res.data as Map<String, dynamic>;
      final biz = BusinessDetail.fromJson(data['data'] as Map<String, dynamic>);
      state = state.copyWith(items: [biz], isLoading: false);
      return biz;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  void clearError() {
    state = state.copyWith();
  }
}

/// Business detail state (full detail with products, services, offers, hours).
class BusinessDetailState {
  final BusinessDetail? detail;
  final List<Product> products;
  final List<Service> services;
  final List<Offer> offers;
  final List<BusinessHour> businessHours;
  final bool isLoading;
  final String? error;

  const BusinessDetailState({
    this.detail,
    this.products = const [],
    this.services = const [],
    this.offers = const [],
    this.businessHours = const [],
    this.isLoading = false,
    this.error,
  });

  BusinessDetailState copyWith({
    BusinessDetail? detail,
    List<Product>? products,
    List<Service>? services,
    List<Offer>? offers,
    List<BusinessHour>? businessHours,
    bool? isLoading,
    String? error,
  }) {
    return BusinessDetailState(
      detail: detail ?? this.detail,
      products: products ?? this.products,
      services: services ?? this.services,
      offers: offers ?? this.offers,
      businessHours: businessHours ?? this.businessHours,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Business detail notifier for fetching full business detail with related data.
class BusinessDetailNotifier extends StateNotifier<BusinessDetailState> {
  BusinessDetailNotifier() : super(const BusinessDetailState());

  Future<void> load(String businessId) async {
    // Clear the prior business immediately so a fast route switch never shows
    // stale catalog, offers, contact details, or operating hours.
    state = const BusinessDetailState(isLoading: true);
    try {
      // Fetch business detail
      final res = await apiClient.get('/businesses/$businessId');
      final data = res.data as Map<String, dynamic>;
      final detail = BusinessDetail.fromJson(
        data['data'] as Map<String, dynamic>,
      );

      // Fetch related data in parallel
      final productsFuture = apiClient.get('/businesses/$businessId/products');
      final servicesFuture = apiClient.get('/businesses/$businessId/services');
      final offersFuture = apiClient.get('/businesses/$businessId/offers');

      final productsRes = await productsFuture;
      final servicesRes = await servicesFuture;
      final offersRes = await offersFuture;

      final productsData = productsRes.data as Map<String, dynamic>;
      final servicesData = servicesRes.data as Map<String, dynamic>;
      final offersData = offersRes.data as Map<String, dynamic>;

      final products =
          (productsData['data'] as List<dynamic>?)
              ?.map((e) => Product.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
      final services =
          (servicesData['data'] as List<dynamic>?)
              ?.map((e) => Service.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
      final offers =
          (offersData['data'] as List<dynamic>?)
              ?.map((e) => Offer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];

      // Business hours are included in detail response
      final businessHours = detail.businessHours;

      state = state.copyWith(
        detail: detail,
        products: products,
        services: services,
        offers: offers,
        businessHours: businessHours,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clear() {
    state = const BusinessDetailState();
  }
}

final businessDetailProvider =
    StateNotifierProvider<BusinessDetailNotifier, BusinessDetailState>((ref) {
      return BusinessDetailNotifier();
    });

/// Favorites state.
class FavoritesState {
  final List<Business> items;
  final bool isLoading;
  final String? error;

  const FavoritesState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  FavoritesState copyWith({
    List<Business>? items,
    bool? isLoading,
    String? error,
  }) {
    return FavoritesState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Favorites notifier.
class FavoritesNotifier extends StateNotifier<FavoritesState> {
  FavoritesNotifier() : super(const FavoritesState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await apiClient.get('/favorites');
      final data = res.data as Map<String, dynamic>;
      final items =
          (data['data'] as List<dynamic>?)
              ?.map((e) => Business.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool?> toggle(String businessId) async {
    try {
      final res = await apiClient.post('/businesses/$businessId/favorite');
      final data = res.data as Map<String, dynamic>;
      final favorited = data['data']['favorited'] as bool;
      if (favorited) {
        // Add to local list
        final detailRes = await apiClient.get('/businesses/$businessId');
        final detailData = detailRes.data as Map<String, dynamic>;
        final biz = Business.fromJson(
          detailData['data'] as Map<String, dynamic>,
        );
        state = state.copyWith(items: [biz, ...state.items]);
      } else {
        // Remove from local list
        state = state.copyWith(
          items: state.items.where((b) => b.id != businessId).toList(),
        );
      }
      return favorited;
    } catch (_) {
      return null;
    }
  }

  Future<bool> clearAll() async {
    final savedItems = List<Business>.of(state.items);
    state = state.copyWith(isLoading: true);
    try {
      for (final business in savedItems) {
        final res = await apiClient.post('/businesses/${business.id}/favorite');
        final data = res.data as Map<String, dynamic>;
        final favorited = data['data']['favorited'] as bool;
        if (favorited) {
          throw StateError('A saved place changed while clearing the list.');
        }
        state = state.copyWith(
          items: state.items.where((item) => item.id != business.id).toList(),
          isLoading: true,
        );
      }
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, FavoritesState>((ref) {
      return FavoritesNotifier();
    });

final businessesProvider =
    StateNotifierProvider<BusinessesNotifier, BusinessesState>((ref) {
      return BusinessesNotifier();
    });

/// Map queries must not replace Explore/search results.
final mapBusinessesProvider =
    StateNotifierProvider.autoDispose<BusinessesNotifier, BusinessesState>(
      (ref) => BusinessesNotifier(),
    );

/// Categories state.
class CategoriesState {
  final List<Category> items;
  final bool isLoading;
  final String? error;

  const CategoriesState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  CategoriesState copyWith({
    List<Category>? items,
    bool? isLoading,
    String? error,
  }) {
    return CategoriesState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Categories notifier.
class CategoriesNotifier extends StateNotifier<CategoriesState> {
  static const defaultCategories = <Category>[
    Category(slug: 'grocery', name: 'Grocery & Kirana', description: 'Fresh groceries, daily provisions and packaged essentials'),
    Category(slug: 'restaurant', name: 'Food & Dining', description: 'Local restaurants, fast food and authentic regional cuisine'),
    Category(slug: 'medical', name: 'Pharmacy & Health', description: 'Medicines, first-aid, healthcare and surgical supplies'),
    Category(slug: 'hardware', name: 'Hardware & Tools', description: 'Tools, paints, sanitaryware and building materials'),
    Category(slug: 'electrician', name: 'Electrician', description: 'Wiring, appliance repairs and electrical installation'),
    Category(slug: 'plumber', name: 'Plumber', description: 'Pipe fittings, drainage, water pumps and leak repair'),
    Category(slug: 'carpenter', name: 'Carpenter', description: 'Custom furniture, wood repairs and interior fitting'),
    Category(slug: 'salon', name: 'Salon & Grooming', description: 'Men & women hair salons, beauty parlours and spa'),
    Category(slug: 'hotel', name: 'Hotels & Lodging', description: 'Hotel rooms, guest houses and verified stays'),
    Category(slug: 'tailor', name: 'Tailoring & Stitching', description: 'Custom tailoring, alterations and dressmaking'),
    Category(slug: 'general', name: 'General Store', description: 'Household goods, stationery, gifting and local retail'),
  ];

  CategoriesNotifier() : super(const CategoriesState(items: defaultCategories)) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await apiClient.get('/categories');
      final data = res.data as Map<String, dynamic>;
      final items =
          (data['data'] as List<dynamic>?)
              ?.map((e) => Category.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
      state = state.copyWith(
        items: items.isNotEmpty ? items : defaultCategories,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        items: state.items.isNotEmpty ? state.items : defaultCategories,
        isLoading: false,
        error: e.toString(),
      );
    }
  }
}

final categoriesProvider =
    StateNotifierProvider<CategoriesNotifier, CategoriesState>((ref) {
      return CategoriesNotifier();
    });

// ---------------------------------------------------------------
// Merchant Workspace Provider
// ---------------------------------------------------------------

/// Merchant service request state.
class MerchantRequestState {
  final List<MerchantServiceRequest> items;
  final bool isLoading;
  final String? error;

  const MerchantRequestState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  MerchantRequestState copyWith({
    List<MerchantServiceRequest>? items,
    bool? isLoading,
    String? error,
  }) {
    return MerchantRequestState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Merchant service request model.
class MerchantServiceRequest {
  final String id;
  final String customerName;
  final String customerPhone;
  final String? serviceName;
  final String description;
  final String? requestedFor;
  final String? requestedLocalDate;
  final String? slotId;
  final String status;
  final String createdAt;
  final String updatedAt;

  const MerchantServiceRequest({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    this.serviceName,
    required this.description,
    this.requestedFor,
    this.requestedLocalDate,
    this.slotId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MerchantServiceRequest.fromJson(Map<String, dynamic> json) {
    return MerchantServiceRequest(
      id: json['id'] as String,
      customerName: json['customer_name'] as String? ?? '',
      customerPhone: json['customer_phone'] as String? ?? '',
      serviceName: json['service_name'] as String?,
      description: json['description'] as String? ?? '',
      requestedFor: json['requested_for'] as String?,
      requestedLocalDate: json['requested_local_date'] as String?,
      slotId: json['slot_id'] as String?,
      status: json['status'] as String? ?? 'requested',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

/// Merchant profile state.
class MerchantProfileState {
  final Map<String, dynamic>? profile;
  final bool isLoading;
  final String? error;

  const MerchantProfileState({
    this.profile,
    this.isLoading = false,
    this.error,
  });

  MerchantProfileState copyWith({
    Map<String, dynamic>? profile,
    bool? isLoading,
    String? error,
  }) {
    return MerchantProfileState(
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Merchant workspace notifier.
class MerchantNotifier extends StateNotifier<MerchantRequestState> {
  MerchantNotifier() : super(const MerchantRequestState());

  Future<void> loadRequests() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await apiClient.get('/merchant/requests');
      final data = res.data as Map<String, dynamic>;
      final items =
          (data['data']['requests'] as List<dynamic>?)
              ?.map(
                (e) =>
                    MerchantServiceRequest.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [];
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> updateRequestStatus(String requestId, String status) async {
    try {
      await apiClient.patch(
        '/merchant/requests/$requestId/status',
        data: {'status': status},
      );
      // Update local state
      state = state.copyWith(
        items: state.items.map((r) {
          if (r.id == requestId) {
            return MerchantServiceRequest(
              id: r.id,
              customerName: r.customerName,
              customerPhone: r.customerPhone,
              serviceName: r.serviceName,
              description: r.description,
              requestedFor: r.requestedFor,
              requestedLocalDate: r.requestedLocalDate,
              slotId: r.slotId,
              status: status,
              createdAt: r.createdAt,
              updatedAt: DateTime.now().toIso8601String(),
            );
          }
          return r;
        }).toList(),
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> rescheduleRequest(
    String businessId,
    String requestId,
    String slotId,
  ) async {
    try {
      await apiClient.patch(
        '/merchant/businesses/$businessId/requests/$requestId/reschedule',
        data: {'slot_id': slotId},
      );
      await loadRequests();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final merchantProvider =
    StateNotifierProvider<MerchantNotifier, MerchantRequestState>((ref) {
      return MerchantNotifier();
    });

/// Merchant profile provider.
final merchantProfileProvider = StateNotifierProvider.autoDispose
    .family<MerchantProfileNotifier, MerchantProfileState, String>(
      (ref, userId) => MerchantProfileNotifier(userId),
    );

class MerchantProfileNotifier extends StateNotifier<MerchantProfileState> {
  MerchantProfileNotifier(this.userId) : super(const MerchantProfileState());

  final String userId;

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await apiClient.get('/merchant/profile');
      final data = res.data as Map<String, dynamic>;
      final profile = data['data'] as Map<String, dynamic>;
      state = state.copyWith(profile: profile, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> update(Map<String, dynamic> updates) async {
    state = state.copyWith(isLoading: true);
    try {
      await apiClient.patch('/merchant/profile', data: updates);
      state = state.copyWith(
        profile: {...?state.profile, ...updates},
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }
}

class MerchantAnalyticsState {
  final int profileViews30d;
  final int productCatalogViews30d;
  final bool isLoading;
  final String? error;

  const MerchantAnalyticsState({
    this.profileViews30d = 0,
    this.productCatalogViews30d = 0,
    this.isLoading = false,
    this.error,
  });

  MerchantAnalyticsState copyWith({
    int? profileViews30d,
    int? productCatalogViews30d,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) => MerchantAnalyticsState(
    profileViews30d: profileViews30d ?? this.profileViews30d,
    productCatalogViews30d:
        productCatalogViews30d ?? this.productCatalogViews30d,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );
}

final merchantAnalyticsProvider =
    StateNotifierProvider<MerchantAnalyticsNotifier, MerchantAnalyticsState>(
      (ref) => MerchantAnalyticsNotifier(),
    );

class MerchantAnalyticsNotifier extends StateNotifier<MerchantAnalyticsState> {
  MerchantAnalyticsNotifier() : super(const MerchantAnalyticsState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await apiClient.get('/merchant/analytics/summary');
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      state = MerchantAnalyticsState(
        profileViews30d: (data['profile_views_30d'] as num?)?.toInt() ?? 0,
        productCatalogViews30d:
            (data['product_catalog_views_30d'] as num?)?.toInt() ?? 0,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }
}

/// Merchant catalog state.
class MerchantCatalogState {
  final List<Product> products;
  final List<Service> services;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final String selectedProductFilter;
  final String selectedServiceFilter;

  const MerchantCatalogState({
    this.products = const [],
    this.services = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.selectedProductFilter = 'all',
    this.selectedServiceFilter = 'all',
  });

  MerchantCatalogState copyWith({
    List<Product>? products,
    List<Service>? services,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? searchQuery,
    String? selectedProductFilter,
    String? selectedServiceFilter,
  }) {
    return MerchantCatalogState(
      products: products ?? this.products,
      services: services ?? this.services,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      selectedProductFilter:
          selectedProductFilter ?? this.selectedProductFilter,
      selectedServiceFilter:
          selectedServiceFilter ?? this.selectedServiceFilter,
    );
  }

  List<Product> get filteredProducts {
    return products.where((p) {
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matches =
            p.name.toLowerCase().contains(q) ||
            (p.description?.toLowerCase().contains(q) ?? false);
        if (!matches) return false;
      }
      switch (selectedProductFilter) {
        case 'in_stock':
          return p.stockStatus == 'in_stock';
        case 'limited':
          return p.stockStatus == 'limited';
        case 'out_of_stock':
          return p.stockStatus == 'out_of_stock';
        case 'published':
          return p.isPublished;
        case 'draft':
          return !p.isPublished;
        default:
          return true;
      }
    }).toList();
  }

  List<Service> get filteredServices {
    return services.where((s) {
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matches =
            s.name.toLowerCase().contains(q) ||
            (s.description?.toLowerCase().contains(q) ?? false);
        if (!matches) return false;
      }
      switch (selectedServiceFilter) {
        case 'active':
          return s.isActive;
        case 'inactive':
          return !s.isActive;
        default:
          return true;
      }
    }).toList();
  }
}

class MerchantCatalogNotifier extends StateNotifier<MerchantCatalogState> {
  MerchantCatalogNotifier() : super(const MerchantCatalogState());

  void setSearchQuery(String q) {
    state = state.copyWith(searchQuery: q);
  }

  void setProductFilter(String filter) {
    state = state.copyWith(selectedProductFilter: filter);
  }

  void setServiceFilter(String filter) {
    state = state.copyWith(selectedServiceFilter: filter);
  }

  Future<void> loadCatalog() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final prodsRes = await apiClient.get('/merchant/products');
      final srvsRes = await apiClient.get('/merchant/services');

      final prodsData = prodsRes.data as Map<String, dynamic>;
      final srvsData = srvsRes.data as Map<String, dynamic>;

      final prodsList =
          (prodsData['data'] as List<dynamic>?)
              ?.map((e) => Product.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final srvsList =
          (srvsData['data'] as List<dynamic>?)
              ?.map((e) => Service.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      state = state.copyWith(
        products: prodsList,
        services: srvsList,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> createProduct({
    required String name,
    String? description,
    double? price,
    String stockStatus = 'in_stock',
    String inventoryMode = 'untracked',
    int? availableQuantity,
    bool isPublished = true,
    String? imageUrl,
  }) async {
    try {
      await apiClient.post(
        '/merchant/products',
        data: {
          'name': name,
          'description': description,
          'price': price,
          'stock_status': stockStatus,
          'inventory_mode': inventoryMode,
          'available_quantity': availableQuantity,
          'is_published': isPublished,
          'image_url': imageUrl,
        },
      );
      await loadCatalog();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateProduct(String id, Map<String, dynamic> updates) async {
    try {
      await apiClient.patch('/merchant/products/$id', data: updates);
      await loadCatalog();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteProduct(String id) async {
    try {
      await apiClient.delete('/merchant/products/$id');
      await loadCatalog();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createService({
    required String name,
    String? description,
    double? priceMin,
    double? priceMax,
    bool isActive = true,
  }) async {
    try {
      await apiClient.post(
        '/merchant/services',
        data: {
          'name': name,
          'description': description,
          'indicative_price_min': priceMin,
          'indicative_price_max': priceMax,
          'is_active': isActive,
        },
      );
      await loadCatalog();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateService(String id, Map<String, dynamic> updates) async {
    try {
      await apiClient.patch('/merchant/services/$id', data: updates);
      await loadCatalog();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteService(String id) async {
    try {
      await apiClient.delete('/merchant/services/$id');
      await loadCatalog();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final merchantCatalogProvider =
    StateNotifierProvider<MerchantCatalogNotifier, MerchantCatalogState>((ref) {
      return MerchantCatalogNotifier();
    });

/// Merchant operating hours and coverage state
class MerchantHoursCoverageState extends Equatable {
  final bool isLoading;
  final bool isSaving;
  final String? error;
  final String? successMessage;
  final List<BusinessHour> hours;
  final int serviceRadiusM;
  final bool acceptsRequests;
  final String businessName;
  final String locality;
  final String city;
  final double latitude;
  final double longitude;

  const MerchantHoursCoverageState({
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.successMessage,
    this.hours = const [],
    this.serviceRadiusM = 5000,
    this.acceptsRequests = true,
    this.businessName = '',
    this.locality = '',
    this.city = '',
    this.latitude = 0,
    this.longitude = 0,
  });

  MerchantHoursCoverageState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    String? successMessage,
    List<BusinessHour>? hours,
    int? serviceRadiusM,
    bool? acceptsRequests,
    String? businessName,
    String? locality,
    String? city,
    double? latitude,
    double? longitude,
  }) {
    return MerchantHoursCoverageState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error,
      successMessage: successMessage,
      hours: hours ?? this.hours,
      serviceRadiusM: serviceRadiusM ?? this.serviceRadiusM,
      acceptsRequests: acceptsRequests ?? this.acceptsRequests,
      businessName: businessName ?? this.businessName,
      locality: locality ?? this.locality,
      city: city ?? this.city,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isSaving,
    error,
    successMessage,
    hours,
    serviceRadiusM,
    acceptsRequests,
    businessName,
    locality,
    city,
    latitude,
    longitude,
  ];
}

class MerchantHoursCoverageNotifier
    extends StateNotifier<MerchantHoursCoverageState> {
  MerchantHoursCoverageNotifier() : super(const MerchantHoursCoverageState()) {
    load();
  }

  static List<BusinessHour> defaultSevenDays() {
    return [
      const BusinessHour(weekday: 1, opensAt: '09:00:00', closesAt: '20:00:00'),
      const BusinessHour(weekday: 2, opensAt: '09:00:00', closesAt: '20:00:00'),
      const BusinessHour(weekday: 3, opensAt: '09:00:00', closesAt: '20:00:00'),
      const BusinessHour(weekday: 4, opensAt: '09:00:00', closesAt: '20:00:00'),
      const BusinessHour(weekday: 5, opensAt: '09:00:00', closesAt: '20:00:00'),
      const BusinessHour(weekday: 6, opensAt: '10:00:00', closesAt: '18:00:00'),
      const BusinessHour(
        weekday: 0,
        opensAt: '09:00:00',
        closesAt: '20:00:00',
        isClosed: true,
      ),
    ];
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      // 1. Load Hours
      try {
        final hoursRes = await apiClient.get('/merchant/operating-hours');
        final hoursData = hoursRes.data as Map<String, dynamic>;
        final rawHours = (hoursData['data'] as List<dynamic>?) ?? [];
        if (rawHours.isNotEmpty) {
          final hoursList = rawHours
              .map((e) => BusinessHour.fromJson(e as Map<String, dynamic>))
              .toList();
          hoursList.sort((a, b) {
            final orderA = a.weekday == 0 ? 7 : a.weekday;
            final orderB = b.weekday == 0 ? 7 : b.weekday;
            return orderA.compareTo(orderB);
          });
          state = state.copyWith(hours: hoursList);
        }
      } catch (_) {
        rethrow;
      }

      // 2. Load Coverage
      try {
        final covRes = await apiClient.get('/merchant/coverage');
        final covData =
            (covRes.data as Map<String, dynamic>)['data']
                as Map<String, dynamic>? ??
            {};
        state = state.copyWith(
          serviceRadiusM:
              (covData['service_radius_m'] as num?)?.toInt() ?? 5000,
          acceptsRequests: covData['accepts_requests'] as bool? ?? true,
          businessName: covData['business_name'] as String? ?? '',
          locality: covData['locality'] as String? ?? '',
          city: covData['city'] as String? ?? '',
          latitude: (covData['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (covData['longitude'] as num?)?.toDouble() ?? 0,
        );
      } catch (_) {}

      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void updateDayHour(
    int weekday, {
    bool? isClosed,
    String? opensAt,
    String? closesAt,
  }) {
    final updated = state.hours.map((h) {
      if (h.weekday == weekday) {
        return BusinessHour(
          weekday: h.weekday,
          opensAt: opensAt ?? h.opensAt,
          closesAt: closesAt ?? h.closesAt,
          isClosed: isClosed ?? h.isClosed,
        );
      }
      return h;
    }).toList();
    state = state.copyWith(hours: updated);
  }

  void initializeHoursDraft() {
    if (state.hours.isEmpty) {
      state = state.copyWith(hours: defaultSevenDays());
    }
  }

  void copyDayToWeekdays(int sourceWeekday) {
    final source = state.hours.firstWhere(
      (h) => h.weekday == sourceWeekday,
      orElse: () => state.hours.first,
    );
    final updated = state.hours.map((h) {
      if (h.weekday >= 1 && h.weekday <= 5) {
        return BusinessHour(
          weekday: h.weekday,
          opensAt: source.opensAt,
          closesAt: source.closesAt,
          isClosed: source.isClosed,
        );
      }
      return h;
    }).toList();
    state = state.copyWith(
      hours: updated,
      successMessage: 'Copied Mon-Fri hours!',
    );
  }

  void setAllDaysOpen(bool isOpen) {
    final updated = state.hours.map((h) {
      return BusinessHour(
        weekday: h.weekday,
        opensAt: h.opensAt ?? '09:00:00',
        closesAt: h.closesAt ?? '20:00:00',
        isClosed: !isOpen,
      );
    }).toList();
    state = state.copyWith(hours: updated);
  }

  void setServiceRadius(int meters) {
    state = state.copyWith(serviceRadiusM: meters);
  }

  void toggleAcceptsRequests(bool accepts) {
    state = state.copyWith(acceptsRequests: accepts);
  }

  Future<bool> saveOperatingHours() async {
    state = state.copyWith(isSaving: true);
    try {
      final payload = {
        'hours': state.hours
            .map(
              (h) => {
                'weekday': h.weekday,
                'opens_at': h.opensAt,
                'closes_at': h.closesAt,
                'is_closed': h.isClosed,
              },
            )
            .toList(),
      };
      await apiClient.put('/merchant/operating-hours', data: payload);
      state = state.copyWith(
        isSaving: false,
        successMessage: 'Operating hours saved successfully',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: 'Failed to save hours: $e',
      );
      return false;
    }
  }

  Future<bool> saveCoverage() async {
    state = state.copyWith(isSaving: true);
    try {
      final payload = {
        'service_radius_m': state.serviceRadiusM,
        'accepts_requests': state.acceptsRequests,
      };
      await apiClient.put('/merchant/coverage', data: payload);
      state = state.copyWith(
        isSaving: false,
        successMessage: 'Service coverage updated successfully',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: 'Failed to save coverage: $e',
      );
      return false;
    }
  }

  void clearMessages() {
    state = state.copyWith();
  }
}

final merchantHoursCoverageProvider =
    StateNotifierProvider<
      MerchantHoursCoverageNotifier,
      MerchantHoursCoverageState
    >((ref) {
      return MerchantHoursCoverageNotifier();
    });

final customerTabIndexProvider = StateProvider<int>((ref) => 0);
