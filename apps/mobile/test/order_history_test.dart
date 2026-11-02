import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/order_history_screen.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';

class TestOrders extends CustomerOrdersNotifier {
  TestOrders() {
    state = [
      CustomerOrder(id: 'GN-FD-07580', businessId: 'test-business', businessName: 'Spice Garden Restaurant', orderType: OrderType.foodDelivery, status: OrderStatus.preparing, createdAt: DateTime(2026), grandTotal: 290, riderName: 'Bikram Mohanty', items: const [CustomerOrderItem(id: 'test-product', name: 'Mughlai Chicken Dum Biryani', price: 290, quantity: 1)]),
      CustomerOrder(id: 'test-table', businessId: 'test-business', businessName: 'Spice Garden Restaurant', orderType: OrderType.tableReservation, status: OrderStatus.confirmed, createdAt: DateTime(2026), grandTotal: 0),
      CustomerOrder(id: 'test-hotel', businessId: 'test-hotel-business', businessName: 'Mayfair Coastal Lagoon & Resort', orderType: OrderType.hotelBooking, status: OrderStatus.confirmed, createdAt: DateTime(2026), grandTotal: 4800),
    ];
  }
}

void main() {
  testWidgets('OrderHistoryScreen renders cards and navigates to tracking', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerOrdersProvider.overrideWith((ref) => TestOrders())],
        child: const MaterialApp(
          home: OrderHistoryScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Screen Title and Cards
    expect(find.text('My Orders & Bookings'), findsOneWidget);
    expect(find.text('Spice Garden Restaurant'), findsNWidgets(4));
    expect(find.text('Mayfair Coastal Lagoon & Resort'), findsNWidgets(2));
    expect(find.text('Preparing (Kitchen)'), findsOneWidget);
    expect(find.text('Confirmed'), findsNWidgets(2));

    // Tap Track Live Delivery to navigate to OrderTrackingScreen
    await tester.tap(find.text('Spice Garden Restaurant').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify OrderTrackingScreen content
    expect(find.byType(OrderTrackingScreen), findsOneWidget);
    expect(find.text('Live Order Tracking'), findsOneWidget);
    expect(find.text('GN-FD-07580'), findsOneWidget);
    expect(find.text('Bikram Mohanty'), findsOneWidget);
    expect(find.text('Delivery Partner'), findsOneWidget);
    expect(find.text('Order Progress'), findsOneWidget);
    expect(find.text('Mughlai Chicken Dum Biryani'), findsOneWidget);
  });
}
