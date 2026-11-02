import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  @override
  void initState() {
    super.initState();
  }

  Future<void> _makeCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(customerOrdersProvider);
    if (orders.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Order details are unavailable.')),
      );
    }
    final order = orders.firstWhere(
      (o) => o.id == widget.orderId,
      orElse: () => orders.first,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.mainText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Live Order Tracking',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.mainText,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            Text(
              order.id,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.help_outline_rounded,
              color: AppTheme.secondaryText,
            ),
            tooltip: 'Support & Help',
            onPressed: () => _showSupportDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location is shown only when the backend supplies tracking data.
            _buildLiveRouteMap(order),

            // 2. ETA & Delivery Progress Stepper
            _buildEtaCard(order),

            // 3. Stage Progression Stepper
            _buildStagesTimeline(order),

            // 4. Delivery Partner Contact Card
            if (order.isDelivery && order.riderName != null)
              _buildRiderCard(order),

            // 5. Delivery Address & Special Instructions
            _buildDeliveryDetailsCard(order),

            // 6. Itemized Order Summary
            _buildOrderReceipt(order),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // --- 1. Interactive Route Map Canvas ---
  Widget _buildLiveRouteMap(CustomerOrder order) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.location_off_outlined, color: AppTheme.primary),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Live courier location is not available for this order.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPin({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.length > 18 ? '${title.substring(0, 16)}...' : title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 9,
                  color: AppTheme.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ],
    );
  }

  // --- 2. ETA Banner Card ---
  Widget _buildEtaCard(CustomerOrder order) {
    final isDelivered = order.status == OrderStatus.delivered;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isDelivered
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isDelivered
                  ? Icons.check_circle_rounded
                  : Icons.delivery_dining_rounded,
              color: isDelivered ? const Color(0xFF16A34A) : AppTheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDelivered ? 'Order Delivered!' : 'Estimated Delivery',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.secondaryText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isDelivered
                      ? 'Delivered'
                      : (order.etaMinutes > 0
                            ? '${order.etaMinutes} min estimate'
                            : 'ETA not available'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isDelivered
                        ? const Color(0xFF16A34A)
                        : AppTheme.mainText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  order.isDelivery
                      ? (order.deliveryAddress ??
                            'Delivery address unavailable')
                      : 'Self pickup at business counter',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. Stages Timeline Stepper ---
  Widget _buildStagesTimeline(CustomerOrder order) {
    final currentIdx = _getStatusStepIndex(order.status);

    final steps = [
      {'title': 'Order Placed', 'desc': 'Kitchen received your order'},
      {'title': 'Preparing Food', 'desc': 'Chef is cooking authentic dishes'},
      {'title': 'Picked Up', 'desc': 'Pickup status reported by the merchant'},
      {'title': 'Out for Delivery', 'desc': 'Delivery is in progress'},
      {'title': 'Delivered', 'desc': 'Package safely delivered'},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Progress',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.mainText,
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < steps.length; i++) ...[
            _buildTimelineStep(
              index: i,
              title: steps[i]['title']!,
              subtitle: steps[i]['desc']!,
              isCompleted: i < currentIdx,
              isActive: i == currentIdx,
              isLast: i == steps.length - 1,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineStep({
    required int index,
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isActive,
    required bool isLast,
  }) {
    Color circleColor;
    IconData icon;

    if (isCompleted) {
      circleColor = const Color(0xFF16A34A);
      icon = Icons.check_rounded;
    } else if (isActive) {
      circleColor = AppTheme.primary;
      icon = Icons.radio_button_checked_rounded;
    } else {
      circleColor = const Color(0xFFCBD5E1);
      icon = Icons.circle_outlined;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isCompleted || isActive ? circleColor : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: circleColor, width: 2),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: 14,
                    color: isCompleted || isActive ? Colors.white : circleColor,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isCompleted
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFE2E8F0),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive || isCompleted
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isActive
                          ? AppTheme.primary
                          : (isCompleted
                                ? AppTheme.mainText
                                : AppTheme.hintText),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive
                          ? AppTheme.mainText
                          : AppTheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 4. Delivery Partner Contact Card ---
  Widget _buildRiderCard(CustomerOrder order) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Partner',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.mainText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.two_wheeler_rounded,
                    color: AppTheme.primary,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.riderName!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.mainText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: Color(0xFFD97706),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                order.riderRating?.toString() ?? 'Not rated',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      order.riderVehicle ?? 'Vehicle details unavailable',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              // Action Buttons
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phone_rounded,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                ),
                onPressed: order.riderPhone == null
                    ? null
                    : () => _makeCall(order.riderPhone!),
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    color: Color(0xFF16A34A),
                    size: 18,
                  ),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Opening chat with ${order.riderName ?? "rider"}...',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 5. Delivery Details Card ---
  Widget _buildDeliveryDetailsCard(CustomerOrder order) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Details',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.mainText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery Address',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.deliveryAddress ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.mainText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (order.specialInstructions != null &&
              order.specialInstructions!.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.note_alt_outlined,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cooking & Delivery Instructions',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        order.specialInstructions!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.mainText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // --- 6. Itemized Order Summary Receipt ---
  Widget _buildOrderReceipt(CustomerOrder order) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Order Summary',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                ),
              ),
              Text(
                '${order.items.length} items',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...order.items.map((item) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: item.isVeg
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: item.isVeg
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.quantity}x',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mainText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.mainText,
                      ),
                    ),
                  ),
                  Text(
                    '₹${item.subtotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mainText,
                    ),
                  ),
                ],
              ),
            );
          }),
          const Divider(height: 20),
          _buildReceiptRow(
            'Item Total',
            '₹${order.itemTotal.toStringAsFixed(0)}',
          ),
          _buildReceiptRow(
            'Delivery Fee',
            order.deliveryFee == 0
                ? 'FREE'
                : '₹${order.deliveryFee.toStringAsFixed(0)}',
          ),
          _buildReceiptRow(
            'Taxes & Packaging',
            '₹${order.tax.toStringAsFixed(0)}',
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Grand Total',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                ),
              ),
              Text(
                '₹${order.grandTotal.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: Color(0xFF16A34A),
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Payment status is not recorded by this service.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.mainText,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper Methods & Dialogs ---
  int _getStatusStepIndex(OrderStatus status) {
    switch (status) {
      case OrderStatus.placed:
        return 0;
      case OrderStatus.preparing:
        return 1;
      case OrderStatus.outForDelivery:
        return 3;
      case OrderStatus.delivered:
      case OrderStatus.completed:
        return 4;
      case OrderStatus.confirmed:
        return 1;
      case OrderStatus.cancelled:
        return 0;
    }
  }

  void _showSupportDialog(BuildContext context) {
    CustomerOrder? order;
    for (final item in ref.read(customerOrdersProvider)) {
      if (item.id == widget.orderId) {
        order = item;
        break;
      }
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Help & Order Support',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need assistance with order ${order?.voucherCode ?? widget.orderId}?',
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.phone_in_talk_rounded,
                color: AppTheme.primary,
              ),
              title: const Text(
                'Call Customer Support',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Support contact is not configured.'),
              onTap: null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.cancel_outlined,
                color: Color(0xFFDC2626),
              ),
              title: const Text(
                'Cancel Order',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFDC2626),
                ),
              ),
              subtitle: const Text('Only permitted during early preparation'),
              onTap: () async {
                Navigator.pop(ctx);
                final cancelled = await ref
                    .read(customerOrdersProvider.notifier)
                    .cancelOrder(widget.orderId);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      cancelled
                          ? 'Order has been cancelled.'
                          : 'This order could not be cancelled.',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}

// Retained map renderer for future backend-supplied courier coordinates.
class _DeliveryMapPainter extends CustomPainter {
  final double pulseValue;
  final OrderStatus orderStatus;

  _DeliveryMapPainter({required this.pulseValue, required this.orderStatus});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Grid / Roads
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke;

    final roadBorderPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke;

    // Draw horizontal and vertical city streets
    final roadPaths = [
      Path()
        ..moveTo(0, size.height * 0.3)
        ..lineTo(size.width, size.height * 0.3),
      Path()
        ..moveTo(0, size.height * 0.75)
        ..lineTo(size.width, size.height * 0.75),
      Path()
        ..moveTo(size.width * 0.25, 0)
        ..lineTo(size.width * 0.25, size.height),
      Path()
        ..moveTo(size.width * 0.7, 0)
        ..lineTo(size.width * 0.7, size.height),
    ];

    for (final p in roadPaths) {
      canvas.drawPath(p, roadBorderPaint);
      canvas.drawPath(p, roadPaint);
    }

    // Delivery Route Polyline
    final routePath = Path();
    final start = Offset(size.width * 0.22, size.height * 0.35);
    final end = Offset(size.width * 0.78, size.height * 0.75);

    routePath.moveTo(start.dx, start.dy);
    routePath.lineTo(size.width * 0.25, size.height * 0.75);
    routePath.lineTo(end.dx, end.dy);

    final routeGlowPaint = Paint()
      ..color = const Color(0xFF2457D6).withValues(alpha: 0.25)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final routeLinePaint = Paint()
      ..color = const Color(0xFF2457D6)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(routePath, routeGlowPaint);
    canvas.drawPath(routePath, routeLinePaint);

    // Rider Position Along Route based on status
    double progress = 0.2;
    if (orderStatus == OrderStatus.preparing) progress = 0.3;
    if (orderStatus == OrderStatus.outForDelivery) {
      progress = 0.3 + (pulseValue * 0.4);
    }
    if (orderStatus == OrderStatus.delivered) progress = 0.95;

    final riderPos = Offset(
      start.dx + (end.dx - start.dx) * progress,
      start.dy + (end.dy - start.dy) * progress,
    );

    // Rider Pulse
    final pulsePaint = Paint()
      ..color = const Color(0xFF2457D6)
          .withValues(alpha: (1.0 - pulseValue) * 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(riderPos, 14 + (pulseValue * 12), pulsePaint);

    // Rider Marker Circle
    final riderBgPaint = Paint()
      ..color = const Color(0xFF2457D6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(riderPos, 12, riderBgPaint);

    final riderBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(riderPos, 12, riderBorder);
  }

  @override
  bool shouldRepaint(covariant _DeliveryMapPainter oldDelegate) => true;
}
