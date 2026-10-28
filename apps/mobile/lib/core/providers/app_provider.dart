import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/constants/app_constants.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

/// Authentication state.
class AuthState {
  final AppUser? user;
  final String? accessToken;
  final bool isLoading;
  final bool isAuthenticated;

  const AuthState({
    this.user,
    this.accessToken,
    this.isLoading = false,
  }) : isAuthenticated = user != null;

  AuthState copyWith({
    AppUser? user,
    String? accessToken,
    bool? isLoading,
  }) {
    return AuthState(
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Auth notifier backed by Riverpod and secure storage.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _loadSession();
  }

  Future<void> _loadSession() async {
    state = state.copyWith(isLoading: true);
    final storage = const FlutterSecureStorage();
    final token = await storage.read(key: AppConstants.accessTokenKey);
    final userJson = await storage.read(key: AppConstants.userKey);
    if (token != null && userJson != null) {
      try {
        final userMap = jsonDecode(userJson) as Map<String, dynamic>;
        state = state.copyWith(
          user: AppUser.fromJson(userMap),
          accessToken: token,
          isLoading: false,
        );
      } catch (_) {
        state = state.copyWith(isLoading: false);
      }
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setSession({required String token, required AppUser user}) async {
    final storage = const FlutterSecureStorage();
    await storage.write(key: AppConstants.accessTokenKey, value: token);
    await storage.write(key: AppConstants.userKey, value: jsonEncode(user.toJson()));
    state = state.copyWith(user: user, accessToken: token, isLoading: false);
  }

  Future<void> logout() async {
    final storage = const FlutterSecureStorage();
    await storage.delete(key: AppConstants.accessTokenKey);
    await storage.delete(key: AppConstants.userKey);
    state = const AuthState();
  }

  /// Request an OTP for the given phone number.
  /// Returns the OTP code when running against the local dev stub.
  Future<Map<String, dynamic>?> requestOTP(String phone) async {
    try {
      final res = await apiClient.post('/auth/otp/request', data: {'phone_e164': phone});
      final data = res.data as Map<String, dynamic>;
      final resultData = data['data'] as Map<String, dynamic>;
      return {
        'phone_e164': resultData['phone_e164'],
        'otp_code': resultData['otp_code'], // dev-only stub
        'status': resultData['status'],
      };
    } catch (e) {
      return null;
    }
  }

  /// Verify an OTP and establish a session.
  Future<bool> verifyOTP(String phone, String otpCode) async {
    try {
      final res = await apiClient.post('/auth/otp/verify', data: {
        'phone_e164': phone,
        'otp_code': otpCode,
      });
      final data = res.data as Map<String, dynamic>;
      final resultData = data['data'] as Map<String, dynamic>;
      final accessToken = resultData['access_token'] as String;
      final refreshToken = resultData['refresh_token'] as String;
      final userMap = resultData['user'] as Map<String, dynamic>;
      final user = AppUser.fromJson(userMap);
      await setSession(token: accessToken, user: user);
      _storeRefreshToken(refreshToken);
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
      items: reset
          ? (items ?? const [])
          : (List<Business>.from(items ?? this.items)..addAll(items ?? const [])),
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

  Future<void> search({
    required String query,
    double? lat,
    double? lng,
    int? radiusM,
    String? categorySlug,
    bool? openNow,
    bool? availableNow,
    String sort = 'relevance',
    bool reset = true,
  }) async {
    if (reset) {
      state = BusinessesState(query: query, isLoading: true);
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final res = await apiClient.get('/businesses', queryParameters: {
        'q': query,
        'lat': lat,
        'lng': lng,
        'radius_m': radiusM ?? 5000,
        'category_slug': categorySlug,
        'open_now': openNow,
        'available_now': availableNow,
        'sort': sort,
        'limit': AppConstants.defaultLimit,
        'cursor': state.cursor,
      });

      final data = res.data as Map<String, dynamic>;
      final items = (data['data'] as List<dynamic>?)
          ?.map((e) => Business.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [];
      final meta = data['meta'] as Map<String, dynamic>?;

      state = state.copyWith(
        items: reset ? items : [...state.items, ...items],
        isLoading: false,
        cursor: meta?['next_cursor'] as String?,
        hasMore: items.length >= AppConstants.defaultLimit,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> nearby({
    required double lat,
    required double lng,
    int radiusM = 5000,
    bool reset = true,
  }) async {
    if (reset) {
      state = const BusinessesState(isLoading: true);
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final res = await apiClient.get('/nearby', queryParameters: {
        'lat': lat,
        'lng': lng,
        'radius_m': radiusM,
        'limit': AppConstants.defaultLimit,
        'cursor': state.cursor,
      });

      final data = res.data as Map<String, dynamic>;
      final items = (data['data'] as List<dynamic>?)
          ?.map((e) => Business.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [];
      final meta = data['meta'] as Map<String, dynamic>?;

      state = state.copyWith(
        items: reset ? items : [...state.items, ...items],
        isLoading: false,
        cursor: meta?['next_cursor'] as String?,
        hasMore: items.length >= AppConstants.defaultLimit,
      );
    } catch (e) {
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
    state = state.copyWith(isLoading: true);
    try {
      // Fetch business detail
      final res = await apiClient.get('/businesses/$businessId');
      final data = res.data as Map<String, dynamic>;
      final detail = BusinessDetail.fromJson(data['data'] as Map<String, dynamic>);

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

      final products = (productsData['data'] as List<dynamic>?)
          ?.map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [];
      final services = (servicesData['data'] as List<dynamic>?)
          ?.map((e) => Service.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [];
      final offers = (offersData['data'] as List<dynamic>?)
          ?.map((e) => Offer.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [];

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

final businessDetailProvider = StateNotifierProvider<BusinessDetailNotifier, BusinessDetailState>((ref) {
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
      final items = (data['data'] as List<dynamic>?)
          ?.map((e) => Business.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [];
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> toggle(String businessId) async {
    try {
      final res = await apiClient.post('/businesses/$businessId/favorite');
      final data = res.data as Map<String, dynamic>;
      final favorited = data['data']['favorited'] as bool;
      if (favorited) {
        // Add to local list
        final detailRes = await apiClient.get('/businesses/$businessId');
        final detailData = detailRes.data as Map<String, dynamic>;
        final biz = Business.fromJson(detailData['data'] as Map<String, dynamic>);
        state = state.copyWith(items: [biz, ...state.items]);
      } else {
        // Remove from local list
        state = state.copyWith(items: state.items.where((b) => b.id != businessId).toList());
      }
      return favorited;
    } catch (e) {
      return false;
    }
  }

  void clear() {
    state = const FavoritesState();
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, FavoritesState>((ref) {
  return FavoritesNotifier();
});

final businessesProvider = StateNotifierProvider<BusinessesNotifier, BusinessesState>((ref) {
  return BusinessesNotifier();
});

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
  CategoriesNotifier() : super(const CategoriesState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await apiClient.get('/categories');
      final data = res.data as Map<String, dynamic>;
      final items = (data['data'] as List<dynamic>?)
              ?.map((e) => Category.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final categoriesProvider = StateNotifierProvider<CategoriesNotifier, CategoriesState>((ref) {
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
      final items = (data['data']['requests'] as List<dynamic>?)
          ?.map((e) => MerchantServiceRequest.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [];
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> updateRequestStatus(String requestId, String status) async {
    try {
      await apiClient.post('/merchant/requests/$requestId/status', data: {'status': status});
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
}

final merchantProvider = StateNotifierProvider<MerchantNotifier, MerchantRequestState>((ref) {
  return MerchantNotifier();
});

/// Merchant profile provider.
final merchantProfileProvider = StateNotifierProvider.autoDispose.family<
  MerchantProfileNotifier, MerchantProfileState, String
>((ref, userId) => MerchantProfileNotifier(userId));

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
    try {
      await apiClient.patch('/merchant/profile', data: updates);
      return true;
    } catch (e) {
      return false;
    }
  }
}
