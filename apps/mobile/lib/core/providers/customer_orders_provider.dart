import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';

class CustomerOrdersNotifier extends StateNotifier<List<CustomerOrder>> {
  CustomerOrdersNotifier() : super(const []);

  void addOrder(CustomerOrder order) {
    state = [order, ...state];
  }

  void updateOrderStatus(String orderId, OrderStatus newStatus) {
    state = [
      for (final order in state)
        if (order.id == orderId) order.copyWith(status: newStatus) else order,
    ];
  }

  void cancelOrder(String orderId) {
    updateOrderStatus(orderId, OrderStatus.cancelled);
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
