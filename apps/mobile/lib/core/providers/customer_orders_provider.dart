import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';

class CustomerOrdersNotifier extends StateNotifier<List<CustomerOrder>> {
  CustomerOrdersNotifier() : super(_initialOrders);

  static final List<CustomerOrder> _initialOrders = [
    CustomerOrder(
      id: 'GN-FD-07580',
      businessId: 'biz-008',
      businessName: 'Spice Garden Restaurant',
      businessLocality: 'Saheed Nagar, Bhubaneswar',
      businessPhone: '+919861000008',
      businessCoverUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=800&q=80',
      orderType: OrderType.foodDelivery,
      status: OrderStatus.preparing,
      createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
      isDelivery: true,
      deliveryAddress: 'Plot 42, Saheed Nagar, Bhubaneswar, 751007',
      specialInstructions: 'Please provide extra green chutney and mint sauce.',
      items: const [
        CustomerOrderItem(
          id: 'prod-008-1',
          name: 'Mughlai Chicken Dum Biryani',
          price: 290.0,
          quantity: 1,
          isVeg: false,
          course: 'Main Course',
        ),
        CustomerOrderItem(
          id: 'prod-008-2',
          name: 'Paneer Butter Masala',
          price: 240.0,
          quantity: 1,
          isVeg: true,
          course: 'Main Course',
        ),
      ],
      itemTotal: 530.0,
      deliveryFee: 0.0, // Free above 500
      tax: 26.5,
      grandTotal: 556.5,
      etaMinutes: 24,
      riderName: 'Bikram Mohanty',
      riderPhone: '+919437108922',
      riderVehicle: 'TVS Raider 125 • OD 02 AB 4921',
      riderRating: 4.9,
    ),
    CustomerOrder(
      id: 'TB-GN-8842',
      businessId: 'biz-008',
      businessName: 'Spice Garden Restaurant',
      businessLocality: 'Saheed Nagar, Bhubaneswar',
      businessPhone: '+919861000008',
      businessCoverUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=800&q=80',
      orderType: OrderType.tableReservation,
      status: OrderStatus.confirmed,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      grandTotal: 0.0,
      tableGuests: 2,
      tableDate: 'Today',
      tableSlot: '07:30 PM (Dinner)',
      seatingArea: 'Indoor AC Lounge',
      voucherCode: '#TB-GN-8842',
    ),
    CustomerOrder(
      id: 'MAYFAIR-PURI-4921',
      businessId: 'biz-009',
      businessName: 'Mayfair Coastal Lagoon & Resort',
      businessLocality: 'Marine Drive, Puri Beach',
      businessPhone: '+916752000009',
      businessCoverUrl: 'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80',
      orderType: OrderType.hotelBooking,
      status: OrderStatus.confirmed,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      grandTotal: 10752.0,
      hotelRoomName: 'Deluxe Sea-Facing King Room',
      hotelNights: 2,
      hotelGuests: 2,
      voucherCode: '#MAYFAIR-PURI-4921',
    ),
  ];

  void addOrder(CustomerOrder order) {
    state = [order, ...state];
  }

  void updateOrderStatus(String orderId, OrderStatus newStatus) {
    state = [
      for (final order in state)
        if (order.id == orderId)
          order.copyWith(status: newStatus)
        else
          order
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
