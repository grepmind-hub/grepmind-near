import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    final token = await const FlutterSecureStorage().read(key: AppConstants.accessTokenKey);
    final userJson = await const FlutterSecureStorage().read(key: AppConstants.userKey);
    if (token != null && userJson != null) {
      // Minimal decode without JWT dependency for MVP; store user from secure storage.
      state = state.copyWith(
        accessToken: token,
        isLoading: false,
      );
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setSession({required String token, required AppUser user}) async {
    await const FlutterSecureStorage().write(key: AppConstants.accessTokenKey, value: token);
    await const FlutterSecureStorage().write(key: AppConstants.userKey, value: user.toJson().toString());
    state = state.copyWith(user: user, accessToken: token, isLoading: false);
  }

  Future<void> logout() async {
    await const FlutterSecureStorage().delete(key: AppConstants.accessTokenKey);
    await const FlutterSecureStorage().delete(key: AppConstants.userKey);
    state = const AuthState();
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

/// Discovery/search state.
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
      items: reset ? (items ?? const []) : (List<Business>.from(items ?? this.items)..addAll(items ?? const [])),
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      cursor: cursor ?? this.cursor,
      error: error ?? this.error,
      query: query ?? this.query,
    );
  }
}

/// Business discovery notifier.
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
      state = BusinessesState(query: query, items: [], cursor: null, hasMore: true, isLoading: true);
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
        error: null,
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
      state = const BusinessesState(items: [], cursor: null, hasMore: true, isLoading: true);
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
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> detail(String id) async {
    try {
      final res = await apiClient.get('/businesses/$id');
      final data = res.data as Map<String, dynamic>;
      final biz = BusinessDetail.fromJson(data['data'] as Map<String, dynamic>);
      state = state.copyWith(items: [biz], isLoading: false, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final businessesProvider = StateNotifierProvider<BusinessesNotifier, BusinessesState>((ref) {
  return BusinessesNotifier();
});
