import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

class CustomerOrdersState {
  final List<CustomerOrder> orders;
  final bool isLoading;
  final bool hasLoaded;
  final bool hasMore;
  final String? nextCursor;
  final String? error;

  const CustomerOrdersState({
    this.orders = const [],
    this.isLoading = false,
    this.hasLoaded = false,
    this.hasMore = false,
    this.nextCursor,
    this.error,
  });

  CustomerOrdersState copyWith({
    List<CustomerOrder>? orders,
    bool? isLoading,
    bool? hasLoaded,
    bool? hasMore,
    String? nextCursor,
    bool clearCursor = false,
    String? error,
    bool clearError = false,
  }) => CustomerOrdersState(
    orders: orders ?? this.orders,
    isLoading: isLoading ?? this.isLoading,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    hasMore: hasMore ?? this.hasMore,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    error: clearError ? null : (error ?? this.error),
  );
}

class CustomerOrdersNotifier extends StateNotifier<CustomerOrdersState> {
  CustomerOrdersNotifier() : super(const CustomerOrdersState());

  String? _ownerUserId;

  Future<void> load({required String? userId}) async {
    final accountChanged = _ownerUserId != null && _ownerUserId != userId;
    _ownerUserId = userId;
    state = CustomerOrdersState(
      orders: accountChanged ? const [] : state.orders,
      isLoading: true,
      hasLoaded: !accountChanged && state.hasLoaded,
    );
    await _fetchPage(userId: userId, append: false);
  }

  Future<void> loadMore({required String? userId}) async {
    if (state.isLoading || !state.hasMore || state.nextCursor == null) return;
    await _fetchPage(userId: userId, append: true);
  }

  Future<void> _fetchPage({
    required String? userId,
    required bool append,
  }) async {
    if (userId == null || userId.isEmpty) {
      state = const CustomerOrdersState(hasLoaded: true);
      return;
    }
    final cursor = append ? state.nextCursor : null;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await apiClient.get(
        '/customer/orders',
        queryParameters: {
          ...?(cursor == null ? null : {'before': cursor}),
          'limit': 20,
        },
      );
      final envelope = response.data as Map<String, dynamic>;
      final rows = (envelope['data'] as List<dynamic>? ?? const [])
          .map((row) => CustomerOrder.fromJson(row as Map<String, dynamic>))
          .toList();
      final meta = envelope['meta'] as Map<String, dynamic>? ?? const {};
      state = CustomerOrdersState(
        orders: append ? [...state.orders, ...rows] : rows,
        hasLoaded: true,
        hasMore: meta['has_more'] as bool? ?? false,
        nextCursor: meta['next_cursor'] as String?,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        error: _message(
          error,
          'Could not load your orders. Check your connection and retry.',
        ),
      );
    }
  }

  Future<CustomerOrder> createOrder(
    String businessId,
    Map<String, dynamic> payload, {
    String? idempotencyKey,
  }) async {
    final response = await apiClient.post(
      '/businesses/$businessId/orders',
      data: payload,
      options: idempotencyKey == null
          ? null
          : Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    final order = CustomerOrder.fromJson(
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>,
    );
    state = state.copyWith(
      orders: [
        order,
        ...state.orders.where((existing) => existing.id != order.id),
      ],
      hasLoaded: true,
    );
    return order;
  }

  Future<CustomerOrder> fetchOrderById(String orderId) async {
    final response = await apiClient.get('/orders/$orderId');
    final order = CustomerOrder.fromJson(
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>,
    );
    state = state.copyWith(
      orders: [
        order,
        ...state.orders.where((existing) => existing.id != order.id),
      ],
      hasLoaded: true,
    );
    return order;
  }

  Future<CustomerOrder?> cancelOrder(String orderId) async {
    try {
      final response = await apiClient.post('/orders/$orderId/cancel');
      final order = CustomerOrder.fromJson(
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>,
      );
      state = state.copyWith(
        orders: [
          order,
          ...state.orders.where((existing) => existing.id != order.id),
        ],
      );
      return order;
    } catch (_) {
      return null;
    }
  }

  Future<bool> submitSupportReport(String orderId, String reason) async {
    try {
      await apiClient.post(
        '/orders/$orderId/support',
        data: {'reason': reason},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  String _message(Object error, String fallback) {
    if (error is DioException && error.response?.data is Map<String, dynamic>) {
      final body = error.response!.data as Map<String, dynamic>;
      final apiError = body['error'] as Map<String, dynamic>?;
      return apiError?['message'] as String? ?? fallback;
    }
    return fallback;
  }
}

final customerOrdersProvider =
    StateNotifierProvider<CustomerOrdersNotifier, CustomerOrdersState>(
      (ref) => CustomerOrdersNotifier(),
    );
