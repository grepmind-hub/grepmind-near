import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

class CustomerOrdersNotifier extends StateNotifier<List<CustomerOrder>> {
  CustomerOrdersNotifier() : super(const []) {
    load();
  }

  Future<void> load() async {
    try {
      final response = await apiClient.get('/customer/orders');
      final rows = (response.data['data'] as List<dynamic>? ?? []);
      state = rows
          .map((row) => CustomerOrder.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      state = const [];
    }
  }

  Future<CustomerOrder> createOrder(
    String businessId,
    Map<String, dynamic> payload,
  ) async {
    final response = await apiClient.post(
      '/businesses/$businessId/orders',
      data: payload,
    );
    final order = CustomerOrder.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
    state = [order, ...state.where((existing) => existing.id != order.id)];
    return order;
  }

  Future<bool> cancelOrder(String orderId) async {
    try {
      final response = await apiClient.post('/orders/$orderId/cancel');
      final order = CustomerOrder.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      state = [
        for (final existing in state)
          if (existing.id == orderId) order else existing,
      ];
      return true;
    } catch (_) {
      return false;
    }
  }

  CustomerOrder? getOrderById(String orderId) {
    try {
      return state.firstWhere((o) => o.id == orderId);
    } catch (_) {
      return null;
    }
  }
}

final customerOrdersProvider =
    StateNotifierProvider<CustomerOrdersNotifier, List<CustomerOrder>>((ref) {
      return CustomerOrdersNotifier();
    });
