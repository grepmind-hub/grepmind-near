import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/screens/order_shopping_hub_screen.dart';

/// Keeps shopping, product-detail and order-history routes inside the Orders
/// workspace so Android Back first returns to the previous shopping surface.
class OrdersTabNavigator extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const OrdersTabNavigator({super.key, required this.navigatorKey});

  @override
  State<OrdersTabNavigator> createState() => _OrdersTabNavigatorState();
}

class _OrdersTabNavigatorState extends State<OrdersTabNavigator> {
  @override
  Widget build(BuildContext context) => Navigator(
    key: widget.navigatorKey,
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const OrderShoppingHubScreen(),
    ),
  );
}
