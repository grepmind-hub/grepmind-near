import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final allOrders = ref.watch(customerOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders & Bookings'),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: allOrders.length,
        itemBuilder: (context, index) {
          final order = allOrders[index];
          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen(orderId: order.id),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.restaurant_rounded, color: AppTheme.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order.businessName,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${order.businessLocality ?? "Bhubaneswar"} • ${order.id}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                              ),
                            ],
                          ),
                        ),
                        _buildStatusPill(order),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      order.businessName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.mainText),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${order.businessLocality ?? "Bhubaneswar"} • ${order.id}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusPill(CustomerOrder order) {
    Color bg;
    Color fg;
    String text;

    switch (order.status) {
      case OrderStatus.placed:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        text = 'Order Placed';
        break;
      case OrderStatus.preparing:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        text = 'Preparing (Kitchen)';
        break;
      case OrderStatus.outForDelivery:
        bg = const Color(0xFFEFF6FF);
        fg = AppTheme.primary;
        text = '🛵 Delivering';
        break;
      case OrderStatus.delivered:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        text = '✓ Delivered';
        break;
      case OrderStatus.confirmed:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        text = 'Confirmed';
        break;
      case OrderStatus.completed:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        text = 'Completed';
        break;
      case OrderStatus.cancelled:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        text = 'Cancelled';
        break;
      default:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        text = 'Unknown';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}