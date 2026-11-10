import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders & bookings'),
        actions: [
          IconButton(
            onPressed: state.isLoading ? null : () => unawaited(_reload()),
            tooltip: 'Refresh orders',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !state.hasLoaded && state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.orders.isEmpty
          ? _ErrorState(
              message: state.error!,
              onRetry: () => unawaited(_reload()),
            )
          : state.orders.isEmpty
          ? const _EmptyOrders()
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (state.error != null)
                    _ErrorBanner(
                      message: state.error!,
                      onRetry: () => unawaited(_reload()),
                    ),
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
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(36),
                      child: Center(
                        child: Text('No orders match these filters.'),
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

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});
  final CustomerOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = switch (order.orderType) {
      OrderType.foodDelivery => 'Food order',
      OrderType.platformOrder =>
        order.platformVertical == 'grocery'
            ? 'Grocery order'
            : 'Grepmind Food order',
      OrderType.tableReservation => 'Table reservation',
      OrderType.hotelBooking => 'Stay booking',
      OrderType.serviceBooking => 'Service booking',
    };
    final icon = switch (order.orderType) {
      OrderType.foodDelivery => Icons.restaurant_outlined,
      OrderType.platformOrder =>
        order.platformVertical == 'grocery'
            ? Icons.shopping_basket_outlined
            : Icons.restaurant_outlined,
      OrderType.tableReservation => Icons.table_restaurant_outlined,
      OrderType.hotelBooking => Icons.hotel_outlined,
      OrderType.serviceBooking => Icons.handyman_outlined,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFD8E2F1)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFEAF0FF),
                child: Icon(icon, color: AppTheme.primary),
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
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mainText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$kind · ${order.createdAt.toLocal().toString().substring(0, 16)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      order.statusDisplay,
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${order.grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.secondaryText,
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
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        for (final value in values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(value),
              selected: selected == value,
              onSelected: (_) => onSelected(value),
            ),
          ),
      ],
    ),
  );
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 54, color: AppTheme.primary),
          SizedBox(height: 16),
          Text(
            'No orders or bookings yet',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Your food orders, reservations, and stays will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
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
    child: ListTile(
      title: const Text('Could not refresh orders'),
      subtitle: Text(message),
      trailing: IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
    ),
  );
}
