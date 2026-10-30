import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/order_history_screen.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';

void main() {
  testWidgets('OrderHistoryScreen renders cards and navigates to tracking', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: OrderHistoryScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Screen Title and Cards
    expect(find.text('My Orders & Bookings'), findsOneWidget);
    expect(find.text('Spice Garden Restaurant'), findsNWidgets(2));
    expect(find.text('Mayfair Coastal Lagoon & Resort'), findsOneWidget);
    expect(find.text('Track Live Delivery'), findsOneWidget);
    expect(find.text('View Booking Voucher'), findsOneWidget);
    expect(find.text('View Stay Voucher'), findsOneWidget);

    // Tap Track Live Delivery to navigate to OrderTrackingScreen
    await tester.tap(find.text('Track Live Delivery'));
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
