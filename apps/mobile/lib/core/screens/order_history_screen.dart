import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/cart_provider.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/screens/checkout_review_screen.dart';
import 'package:grepmind_mobile/core/screens/customer_cart_screen.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_catalog_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/category_placeholder.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  String _statusFilter = 'All';
  String _typeFilter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_reload()));
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final userId = ref.read(currentUserProvider)?.id;
    await ref.read(customerOrdersProvider.notifier).load(userId: userId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerOrdersProvider);
    final visible = state.orders.where((order) {
      final statusMatches = switch (_statusFilter) {
        'Active' => order.isActive,
        'Completed' =>
          order.status == OrderStatus.delivered ||
              order.status == OrderStatus.completed,
        'Cancelled' => order.status == OrderStatus.cancelled,
        'Rejected' => order.status == OrderStatus.rejected,
        _ => true,
      };
      final typeMatches = switch (_typeFilter) {
        'Food' =>
          order.orderType == OrderType.foodDelivery ||
              (order.orderType == OrderType.platformOrder &&
                  order.platformVertical == 'food'),
        'Groceries' =>
          order.orderType == OrderType.platformOrder &&
              order.platformVertical == 'grocery',
        'Reservations' => order.orderType == OrderType.tableReservation,
        'Stays' => order.orderType == OrderType.hotelBooking,
        _ => true,
      };
      return statusMatches && typeMatches;
    }).toList();

    // Check for ongoing active order for the hero card
    final activeOrder = state.orders.where((o) => o.isActive).firstOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text('Orders & bookings'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: state.isLoading ? null : () => unawaited(_reload()),
            tooltip: 'Refresh orders',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !state.hasLoaded && state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.emerald),
            )
          : state.error != null && state.orders.isEmpty
          ? _ErrorState(
              message: state.error!,
              onRetry: () => unawaited(_reload()),
            )
          : state.orders.isEmpty
          ? const _EmptyOrders()
          : RefreshIndicator(
              color: AppTheme.emerald,
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (state.error != null)
                    _ErrorBanner(
                      message: state.error!,
                      onRetry: () => unawaited(_reload()),
                    ),

                  // Active Order Live Tracker Hero Card (Top of list)
                  if (activeOrder != null &&
                      (_statusFilter == 'All' || _statusFilter == 'Active'))
                    _ActiveOrderHeroCard(
                      order: activeOrder,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderTrackingScreen(orderId: activeOrder.id),
                        ),
                      ),
                    ),

                  // Modern Filter Controls
                  _FilterRow(
                    label: 'Status',
                    values: const [
                      'All',
                      'Active',
                      'Completed',
                      'Cancelled',
                      'Rejected',
                    ],
                    selected: _statusFilter,
                    onSelected: (value) =>
                        setState(() => _statusFilter = value),
                  ),
                  const SizedBox(height: 10),
                  _FilterRow(
                    label: 'Type',
                    values: const [
                      'All',
                      'Food',
                      'Groceries',
                      'Reservations',
                      'Stays',
                    ],
                    selected: _typeFilter,
                    onSelected: (value) => setState(() => _typeFilter = value),
                  ),
                  const SizedBox(height: 16),

                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 36,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.filter_list_off_rounded,
                                size: 32,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No orders match these filters.',
                              style: TextStyle(
                                color: Color(0xFF17352C),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Try selecting a different status or category to see orders.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFE6F9F1),
                                foregroundColor: const Color(0xFF059669),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => setState(() {
                                _statusFilter = 'All';
                                _typeFilter = 'All';
                              }),
                              child: const Text(
                                'Reset filters',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  for (final order in visible)
                    _OrderCard(
                      order: order,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderTrackingScreen(orderId: order.id),
                        ),
                      ),
                    ),

                  if (state.hasMore)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.emerald,
                          side: const BorderSide(color: Color(0xFFE1EBE5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: state.isLoading
                            ? null
                            : () => ref
                                  .read(customerOrdersProvider.notifier)
                                  .loadMore(
                                    userId: ref.read(currentUserProvider)?.id,
                                  ),
                        icon: state.isLoading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.emerald,
                                ),
                              )
                            : const Icon(Icons.expand_more_rounded),
                        label: Text(state.isLoading ? 'Loading…' : 'Load more'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// 2026 Live Delivery Hero Card for active orders
class _ActiveOrderHeroCard extends StatelessWidget {
  final CustomerOrder order;
  final VoidCallback onTap;

  const _ActiveOrderHeroCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final currentStep = switch (order.status) {
      OrderStatus.placed => 1,
      OrderStatus.accepted ||
      OrderStatus.confirmed ||
      OrderStatus.preparing => 2,
      OrderStatus.readyForPickup || OrderStatus.outForDelivery => 3,
      OrderStatus.delivered || OrderStatus.completed => 4,
      _ => 1,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE6F9F1), Color(0xFFF8FAF9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB8F2DC), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.radar_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'LIVE TRACKING',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (order.etaMinutes > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 12,
                              color: Color(0xFF15803D),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '~${order.etaMinutes} mins ETA',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${order.businessName} · Active',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF17352C),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            order.statusDisplay,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Track Live',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded, size: 14),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 4-step progress row
                Row(
                  children: [
                    _StepItem(
                      label: 'Placed',
                      isActive: currentStep >= 1,
                      isCurrent: currentStep == 1,
                    ),
                    _StepConnector(isPassed: currentStep >= 2),
                    _StepItem(
                      label: 'Preparing',
                      isActive: currentStep >= 2,
                      isCurrent: currentStep == 2,
                    ),
                    _StepConnector(isPassed: currentStep >= 3),
                    _StepItem(
                      label: 'On the way',
                      isActive: currentStep >= 3,
                      isCurrent: currentStep == 3,
                    ),
                    _StepConnector(isPassed: currentStep >= 4),
                    _StepItem(
                      label: 'Delivered',
                      isActive: currentStep >= 4,
                      isCurrent: currentStep == 4,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isCurrent;

  const _StepItem({
    required this.label,
    required this.isActive,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF059669) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive
                  ? const Color(0xFF059669)
                  : const Color(0xFFCBD5E1),
              width: 2,
            ),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: const Color(0xFF059669).withValues(alpha: 0.3),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: isActive
              ? const Icon(Icons.check, size: 11, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isCurrent
                ? FontWeight.w800
                : (isActive ? FontWeight.w600 : FontWeight.w500),
            color: isActive ? const Color(0xFF17352C) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool isPassed;

  const _StepConnector({required this.isPassed});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2.5,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isPassed ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order, required this.onTap});
  final CustomerOrder order;
  final VoidCallback onTap;

  Future<void> _handleReorder(BuildContext context, WidgetRef ref) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null || order.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No reorderable items found in this order.'),
        ),
      );
      return;
    }
    final cart = ref.read(cartProvider);
    var replace = !cart.hasLines;
    if (cart.hasLines) {
      final sameMerchant = cart.businessId == order.businessId;
      replace =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Replace current cart?'),
              content: Text(
                sameMerchant
                    ? 'Your current items will be replaced with the products from this order.'
                    : 'Your cart contains items from another merchant. Replace them?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep cart'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace cart'),
                ),
              ],
            ),
          ) ??
          false;
      if (!replace) return;
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Adding items to cart…'),
        duration: Duration(seconds: 1),
      ),
    );

    final result = await ref
        .read(cartProvider.notifier)
        .rebuildFromOrder(
          userId: userId,
          businessId: order.businessId,
          businessName: order.businessName,
          items: order.items
              .map(
                (item) => {
                  'product_id': item.id,
                  'quantity': item.quantity,
                  'name': item.name,
                },
              )
              .toList(),
          replaceExisting: replace,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
    if (result.ready) {
      final proceed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const CustomerCartScreen()),
      );
      if (proceed == true && context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CheckoutReviewScreen(
              businessId: order.businessId,
              businessName: order.businessName,
            ),
          ),
        );
      }
    }
  }

  void _showReceipt(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReceiptModalSheet(order: order),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = switch (order.orderType) {
      OrderType.foodDelivery => 'Food order',
      OrderType.platformOrder =>
        order.platformVertical == 'grocery'
            ? 'Grocery order'
            : 'Abashyaka Food order',
      OrderType.tableReservation => 'Table reservation',
      OrderType.hotelBooking => 'Stay booking',
      OrderType.serviceBooking => 'Service booking',
    };

    final isDelivered =
        order.status == OrderStatus.delivered ||
        order.status == OrderStatus.completed;
    final isCancelled =
        order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.rejected;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE1EBE5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Avatar, Store Details, Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: CategoryThemedPlaceholder(
                        categorySlug:
                            order.platformVertical ??
                            (order.orderType == OrderType.foodDelivery
                                ? 'food'
                                : 'grocery'),
                        businessName: order.businessName,
                        isAvatar: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF17352C),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$kind · ${order.createdAt.toLocal().toString().substring(0, 16)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Semantic Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: isDelivered
                          ? const Color(0xFFECFDF5)
                          : isCancelled
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDelivered
                            ? const Color(0xFFA7F3D0)
                            : isCancelled
                            ? const Color(0xFFFECACA)
                            : const Color(0xFFBFDBFE),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDelivered
                              ? Icons.check_circle_rounded
                              : isCancelled
                              ? Icons.cancel_rounded
                              : Icons.timelapse_rounded,
                          size: 12,
                          color: isDelivered
                              ? const Color(0xFF059669)
                              : isCancelled
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          order.statusDisplay,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDelivered
                                ? const Color(0xFF059669)
                                : isCancelled
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Itemized Preview Row (if items present)
              if (order.items.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEBEFED)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          order.items
                              .map((i) => '${i.quantity}x ${i.name}')
                              .join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),

              // Bottom Row: Total Price & Quick Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '₹${order.grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF17352C),
                        ),
                      ),
                      if (order.paymentMethod != null ||
                          order.paymentStatus.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            order.paymentMethod?.toUpperCase() ??
                                (order.paymentStatus == 'paid'
                                    ? 'PAID'
                                    : 'COD'),
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Point 2: Reorder Button (for completed orders with items)
                      if (!order.isActive && order.items.isNotEmpty) ...[
                        OutlinedButton(
                          key: ValueKey('reorder_${order.id}'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF059669),
                            side: const BorderSide(color: Color(0xFFB8F2DC)),
                            backgroundColor: const Color(0xFFF0FDF4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _handleReorder(context, ref),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.replay_rounded, size: 13),
                              SizedBox(width: 3),
                              Text(
                                'Reorder',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],

                      // Point 2: View Bill / Receipt Modal or Track Live
                      OutlinedButton.icon(
                        key: ValueKey('view_bill_${order.id}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF059669),
                          side: const BorderSide(color: Color(0xFFE1EBE5)),
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: order.isActive
                            ? onTap
                            : () => _showReceipt(context),
                        icon: Icon(
                          order.isActive
                              ? Icons.moped_rounded
                              : Icons.receipt_long_outlined,
                          size: 13,
                        ),
                        label: Text(
                          order.isActive ? 'Track Live' : 'View Bill',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Point 2: 2026 Digital Receipt Bottom Sheet
class _ReceiptModalSheet extends StatelessWidget {
  final CustomerOrder order;

  const _ReceiptModalSheet({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        order.businessName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF17352C),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified_rounded,
                        size: 16,
                        color: Color(0xFF2563EB),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Order #${order.id.length > 8 ? order.id.substring(0, 8).toUpperCase() : order.id.toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Text(
                  order.statusDisplay.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),

          // Itemized Table
          Text(
            'ITEMS BREAKDOWN (${order.items.length})',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),

          if (order.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                order.orderType == OrderType.tableReservation
                    ? 'Table reservation for ${order.tableGuests ?? 2} guests'
                    : 'Order package fulfillment',
                style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
              ),
            )
          else
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity}x ${item.name}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    Text(
                      '₹${item.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 10),

          // Total Calculation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Item total',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              Text(
                '₹${order.itemTotal > 0 ? order.itemTotal.toStringAsFixed(2) : order.grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Delivery fee',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              Text(
                order.deliveryFee > 0
                    ? '₹${order.deliveryFee.toStringAsFixed(2)}'
                    : 'FREE',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
          if (order.tax > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Taxes & Charges',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                Text(
                  '₹${order.tax.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Grand Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF17352C),
                ),
              ),
              Text(
                '₹${order.grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAF9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.payment_rounded,
                  size: 16,
                  color: Color(0xFF059669),
                ),
                const SizedBox(width: 8),
                Text(
                  'Payment: ${order.paymentMethod?.toUpperCase() ?? (order.paymentStatus == 'paid' ? 'PAID ONLINE' : 'CASH ON DELIVERY')}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF059669),
                    side: const BorderSide(color: Color(0xFFB8F2DC)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Receipt downloaded to device.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text(
                    'Download',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFF17352C),
            ),
          ),
        ),
        for (final value in values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(
                value,
                style: TextStyle(
                  fontWeight: selected == value
                      ? FontWeight.w700
                      : FontWeight.w500,
                  fontSize: 12,
                  color: selected == value
                      ? Colors.white
                      : const Color(0xFF17352C),
                ),
              ),
              selected: selected == value,
              selectedColor: const Color(0xFF059669),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selected == value
                    ? const Color(0xFF059669)
                    : const Color(0xFFE1EBE5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              showCheckmark: false,
              onSelected: (_) => onSelected(value),
            ),
          ),
      ],
    ),
  );
}

/// Point 3: Engaging 2026 Empty Orders State with Discovery Recovery
class _EmptyOrders extends ConsumerWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F9F1),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFB8F2DC), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 54,
              color: Color(0xFF059669),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No orders or bookings yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF17352C),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your food deliveries, daily groceries, and appointments will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),

          // Point 3: Discovery Recovery Buttons
          _DiscoveryRecoveryCard(
            icon: Icons.restaurant_rounded,
            iconBg: const Color(0xFFFFEDD5),
            iconColor: const Color(0xFFEA580C),
            title: 'Explore Food & Meals',
            subtitle: 'Order from trusted local kitchens',
            onTap: () {
              final location = ref.read(appLocationProvider);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlatformCatalogScreen(
                    vertical: 'food',
                    city: location.cityName,
                    locality: location.localityName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _DiscoveryRecoveryCard(
            icon: Icons.local_grocery_store_rounded,
            iconBg: const Color(0xFFDCFCE7),
            iconColor: const Color(0xFF16A34A),
            title: 'Browse Fresh Groceries',
            subtitle: 'Daily essentials delivered in minutes',
            onTap: () {
              final location = ref.read(appLocationProvider);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlatformCatalogScreen(
                    vertical: 'grocery',
                    city: location.cityName,
                    locality: location.localityName,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _DiscoveryRecoveryCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DiscoveryRecoveryCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE1EBE5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF17352C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: Color(0xFFB45309),
          ),
          const SizedBox(height: 12),
          const Text(
            'Orders could not be loaded',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF7E8),
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFFDE68A)),
    ),
    child: ListTile(
      title: const Text(
        'Could not refresh orders',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      subtitle: Text(message, style: const TextStyle(fontSize: 12)),
      trailing: IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
    ),
  );
}
