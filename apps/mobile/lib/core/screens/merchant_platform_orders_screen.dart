import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Screen 9: Orders Hub & Fulfillment Pipeline
/// Screen 10: Order Detail & Kitchen Ticket
/// Screen 11: Order Handover & Pickup Verification
/// Showcase Screen 23: Merchant Order Details & Fulfillment
class MerchantPlatformOrdersScreen extends ConsumerStatefulWidget {
  const MerchantPlatformOrdersScreen({super.key});

  @override
  ConsumerState<MerchantPlatformOrdersScreen> createState() =>
      _MerchantPlatformOrdersScreenState();
}

class _MerchantPlatformOrdersScreenState
    extends ConsumerState<MerchantPlatformOrdersScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _dispatchRefreshInterval = Duration(seconds: 8);

  String? _businessId;
  String? _error;
  String? _dispatchError;
  bool _loading = true;
  bool _dispatchRefreshing = false;
  String? _busyOrder;
  String? _confirmingPickupOrder;
  List<Map<String, dynamic>> _orders = const [];
  Map<String, Map<String, dynamic>> _dispatchByOrder = const {};
  Timer? _dispatchRefreshTimer;

  late TabController _tabController;
  final List<String> _tabs = const [
    'All',
    'New Orders',
    'Preparing',
    'Ready for Pickup',
    'History',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dispatchRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final businessId = _businessId;
      if (businessId != null && _hasReadyOrders) {
        _refreshDispatch(businessId);
      }
      _startDispatchRefreshTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _dispatchRefreshTimer?.cancel();
      _dispatchRefreshTimer = null;
    }
  }

  bool get _hasReadyOrders =>
      _orders.any((order) => order['status'] == 'ready_for_pickup');

  void _startDispatchRefreshTimer() {
    _dispatchRefreshTimer?.cancel();
    _dispatchRefreshTimer = null;
    if (!_hasReadyOrders || _businessId == null) return;
    _dispatchRefreshTimer = Timer.periodic(_dispatchRefreshInterval, (_) {
      final businessId = _businessId;
      if (mounted && businessId != null && _hasReadyOrders) {
        _refreshDispatch(businessId);
      }
    });
  }

  Future<void> _initialize() async {
    var profile = ref.read(merchantProfileProvider('')).profile;
    if (profile == null) {
      await ref.read(merchantProfileProvider('').notifier).load();
      profile = ref.read(merchantProfileProvider('')).profile;
    }
    final id = profile?['id'] as String?;
    if (id == null || id.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'Choose an approved merchant business to view its assigned orders.';
          _loading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _businessId = id);
    await _refresh();
  }

  Future<void> _refresh() async {
    final businessId = _businessId;
    if (businessId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await apiClient.get(
        '/merchant/businesses/$businessId/platform-orders',
        queryParameters: const {'limit': 50},
      );
      final data =
          (response.data as Map<String, dynamic>)['data'] as List<dynamic>? ??
          const [];
      if (!mounted) return;
      setState(() => _orders = data.cast<Map<String, dynamic>>());
      await _refreshDispatch(businessId);
      _startDispatchRefreshTimer();
    } catch (error) {
      if (mounted) setState(() => _error = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshDispatch(String businessId) async {
    if (_dispatchRefreshing) return;
    _dispatchRefreshing = true;
    try {
      final response = await apiClient.get(
        '/merchant/businesses/$businessId/delivery-dispatch',
      );
      final data =
          (response.data as Map<String, dynamic>)['data'] as List<dynamic>? ??
          const [];
      if (!mounted) return;
      final nextDispatch = {
        for (final row in data.cast<Map<String, dynamic>>())
          if (row['order_id'] is String) row['order_id'] as String: row,
      };
      final unchanged =
          nextDispatch.length == _dispatchByOrder.length &&
          nextDispatch.entries.every((entry) {
            final previous = _dispatchByOrder[entry.key];
            final next = entry.value;
            return previous != null &&
                previous['job_id'] == next['job_id'] &&
                previous['execution_state'] == next['execution_state'] &&
                previous['rider_assigned'] == next['rider_assigned'] &&
                previous['rider_name'] == next['rider_name'] &&
                previous['delivery_state'] == next['delivery_state'];
          });
      if (unchanged && _dispatchError == null) return;
      setState(() {
        _dispatchByOrder = nextDispatch;
        _dispatchError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          // Fail closed: stale eligibility must never expose a pickup-code action.
          _dispatchByOrder = const {};
          _dispatchError = 'Delivery handover status is unavailable. Refresh before issuing a code.';
        });
      }
    } finally {
      _dispatchRefreshing = false;
    }
  }

  Future<void> _issuePickupCode(Map<String, dynamic> order) async {
    final orderId = order['id'] as String?;
    final businessId = _businessId;
    final summary = orderId == null ? null : _dispatchByOrder[orderId];
    final jobId = summary?['job_id'] as String?;
    final reference = order['reference_code'] as String? ?? 'this order';
    if (businessId == null ||
        orderId == null ||
        jobId == null ||
        _busyOrder != null ||
        _confirmingPickupOrder != null) {
      return;
    }

    setState(() => _confirmingPickupOrder = orderId);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Issue pickup code?'),
          content: Text(
            'Confirm order $reference is ready and the assigned rider is physically at your pickup location. The short-lived code can be used to verify this handover.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.emerald,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Issue code'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() {
        _confirmingPickupOrder = null;
        _busyOrder = orderId;
        _dispatchError = null;
      });
      final response = await apiClient.post(
        '/merchant/businesses/$businessId/delivery-jobs/$jobId/pickup-code',
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final code = data['pickup_code'] as String?;
      final expires = data['expires_in_seconds'] as int?;
      if (code == null || code.length != 8 || expires == null || expires <= 0) {
        throw const FormatException('Invalid pickup code response.');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PickupCodeDialog(
          reference: reference,
          code: code,
          expiresInSeconds: expires,
        ),
      );
      await _refreshDispatch(businessId);
    } catch (error) {
      if (mounted) {
        setState(() => _dispatchError = _apiMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (_busyOrder == orderId) _busyOrder = null;
          if (_confirmingPickupOrder == orderId) {
            _confirmingPickupOrder = null;
          }
        });
      }
    }
  }

  Future<void> _act(
    Map<String, dynamic> order,
    String action, {
    String? reason,
  }) async {
    final businessId = _businessId;
    final orderId = order['id'] as String?;
    if (businessId == null || orderId == null || _busyOrder != null) return;
    setState(() {
      _busyOrder = orderId;
      _error = null;
    });
    try {
      await apiClient.post(
        '/merchant/businesses/$businessId/platform-orders/$orderId/$action',
        data: action == 'reject' ? {'reason': reason} : null,
      );
      await _refresh();
      if (mounted) {
        final label = switch (action) {
          'accept' => 'Order accepted.',
          'prepare' => 'Preparation started.',
          'ready' => 'Order marked ready for pickup.',
          _ => 'Order rejected. The reason was recorded and reserved stock released.',
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(label)));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _busyOrder = null);
    }
  }

  Future<void> _reject(Map<String, dynamic> order) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject platform order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The reason is saved and sent to the customer. Reserved stock is released once. No reassignment or refund happens automatically.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason (10–500 characters)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AbashyakaColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.length >= 10 && text.length <= 500) {
                Navigator.pop(context, text);
              }
            },
            child: const Text('Confirm rejection'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason != null && mounted) await _act(order, 'reject', reason: reason);
  }

  String _apiMessage(Object error) {
    if (error is DioException && error.response?.data is Map<String, dynamic>) {
      final body = error.response!.data as Map<String, dynamic>;
      return (body['error'] as Map<String, dynamic>?)?['message'] as String? ??
          'Unable to load or update platform orders.';
    }
    return 'Unable to load or update platform orders. Check your connection and retry.';
  }

  List<Map<String, dynamic>> _filteredOrders(int tabIndex) {
    switch (tabIndex) {
      case 1: // New Orders
        return _orders.where((o) => o['status'] == 'placed').toList();
      case 2: // Preparing
        return _orders
            .where(
              (o) => o['status'] == 'accepted' || o['status'] == 'preparing',
            )
            .toList();
      case 3: // Ready for Pickup
        return _orders.where((o) => o['status'] == 'ready_for_pickup').toList();
      case 4: // History / Completed
        return _orders
            .where(
              (o) =>
                  o['status'] == 'delivered' ||
                  o['status'] == 'cancelled' ||
                  o['status'] == 'rejected',
            )
            .toList();
      case 0: // All
      default:
        return _orders;
    }
  }

  int _countForTab(int tabIndex) {
    return _filteredOrders(tabIndex).length;
  }

  @override
  Widget build(BuildContext context) {
    final activeTabOrders = _filteredOrders(_tabController.index);

    return Scaffold(
      backgroundColor: AbashyakaColors.pearlWhite,
      appBar: AppBar(
        backgroundColor: AbashyakaColors.pureWhite,
        foregroundColor: AppTheme.mainText,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orders & Fulfillment',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AbashyakaColors.primaryText,
              ),
            ),
            Text(
              'Partner Orders Pipeline · Abashyaka',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            tooltip: 'Refresh orders',
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.emerald),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: const BoxDecoration(
              color: AbashyakaColors.pureWhite,
              border: Border(
                bottom: BorderSide(color: AbashyakaColors.aquaSilverBorder),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppTheme.emerald,
              indicatorWeight: 3,
              labelColor: AppTheme.emerald,
              unselectedLabelColor: AppTheme.secondaryText,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                _buildTab('All', _countForTab(0)),
                _buildTab('New Orders', _countForTab(1)),
                _buildTab('Preparing', _countForTab(2)),
                _buildTab('Ready for Pickup', _countForTab(3)),
                _buildTab('History', _countForTab(4)),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.emerald,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // Screen 9 Header Summary Card
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AbashyakaColors.verifiedSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AbashyakaColors.aquaSilverBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AbashyakaColors.pureWhite,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: AppTheme.emerald,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Partner Fulfillment Orders',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_orders.length} total orders · ${_countForTab(1)} awaiting response',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AbashyakaColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AbashyakaColors.pureWhite,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AbashyakaColors.aquaSilverBorder,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: AbashyakaColors.success,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Store Open',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AbashyakaColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AbashyakaColors.error),
                ),
                color: AbashyakaColors.errorSurface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AbashyakaColors.error),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_dispatchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Card(
                  elevation: 0,
                  color: AbashyakaColors.warningSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(
                      color: AbashyakaColors.warningSurface,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: AbashyakaColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dispatchError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AbashyakaColors.warning,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (_loading && _orders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.emerald),
                ),
              ),

            if (!_loading && _error == null && activeTabOrders.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 64),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: AbashyakaColors.verifiedSurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        size: 36,
                        color: AppTheme.emerald,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No assigned platform orders',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mainText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'New orders will appear after Abashyaka assigns your business to fulfill the complete basket.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Order cards in current tab
            for (final order in activeTabOrders) _orderCard(order),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AbashyakaColors.verifiedSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.emerald,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? 'placed';
    final paymentMethod = order['payment_method']?.toString() ?? '';
    final paymentStatus =
        order['payment_status']?.toString() ?? 'not_collected';
    final codState =
        order['cod_collection_state']?.toString() ?? 'not_applicable';
    final fulfillmentPaymentAllowed = switch (paymentMethod) {
      'upi' => paymentStatus == 'paid',
      'cash_on_delivery' => codState == 'due' || codState == 'collected',
      _ => true,
    };
    final items = (order['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final busy = _busyOrder == order['id'];
    final confirmingPickup = _confirmingPickupOrder == order['id'];
    final dispatch = _dispatchByOrder[order['id']];
    final isGrocery = order['vertical'] == 'grocery';
    final vertical = isGrocery ? 'Grocery order' : 'Food order';
    final fulfillment = switch (order['fulfillment_type']) {
      'delivery' => 'Delivery',
      'takeaway' || 'pickup' => 'Customer pickup',
      _ => null,
    };
    final statusLabel = _statusLabel(status);
    final events = (order['status_events'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((event) => event['status'] is String)
        .toList();

    return Card(
      color: AbashyakaColors.pureWhite,
      margin: const EdgeInsets.only(top: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AbashyakaColors.aquaSilverBorder),
      ),
      child: ExpansionTile(
        key: PageStorageKey('merchant-order-${order['id']}'),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isGrocery
                ? AbashyakaColors.informationSurface
                : AbashyakaColors.verifiedSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isGrocery
                ? Icons.shopping_basket_outlined
                : Icons.restaurant_outlined,
            color: isGrocery ? AbashyakaColors.information : AppTheme.emerald,
            size: 22,
          ),
        ),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              vertical,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppTheme.mainText,
              ),
            ),
            _buildStatusPill(status, statusLabel),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${order['reference_code'] ?? 'Platform order'} · ${order['delivery_locality'] ?? ''}, ${order['delivery_district'] ?? ''}\n$statusLabel',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.secondaryText,
              height: 1.3,
            ),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(color: AbashyakaColors.aquaSilverBorder),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              fulfillment == null
                  ? 'Order details'
                  : 'Order details · $fulfillment',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AbashyakaColors.primaryText,
              ),
            ),
          ),

          // Payment details row
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AbashyakaColors.unavailableSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.payments_outlined,
                size: 18,
                color: AppTheme.secondaryText,
              ),
            ),
            title: Text(
              _paymentLabel(order),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            subtitle: Text(
              _paymentDetail(order),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryText,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.receipt_outlined, size: 14),
              label: const Text(
                'Kitchen Ticket',
                style: TextStyle(fontSize: 12),
              ),
              onPressed: () => _showKitchenTicketModal(order),
            ),
          ),

          // Items breakdown
          const SizedBox(height: 4),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AbashyakaColors.verifiedSurface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '× ${item['quantity']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: AppTheme.emerald,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['product_name'] as String? ?? 'Product',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.mainText,
                          ),
                        ),
                        if ((item['variant_name'] ?? item['unit_label']) !=
                            null)
                          Text(
                            '${item['variant_name'] ?? ''} · ${item['unit_label'] ?? ''}',
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
            ),

          if ((order['special_instructions'] as String? ?? '').isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AbashyakaColors.warningSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AbashyakaColors.warningSurface),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.note_alt_outlined,
                    size: 16,
                    color: AbashyakaColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Instructions: ${order['special_instructions']}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AbashyakaColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (events.isNotEmpty) _orderTimeline(events, status),
          const SizedBox(height: 10),

          // Stage transitions
          if (status == 'placed')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AbashyakaColors.error,
                      side: const BorderSide(color: AbashyakaColors.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: busy ? null : () => _reject(order),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.emerald,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: busy || !fulfillmentPaymentAllowed
                        ? null
                        : () => _act(order, 'accept'),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),

          if (status == 'placed' && !fulfillmentPaymentAllowed)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'UPI payment must be verified before this order can be accepted.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AbashyakaColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          if (status == 'accepted')
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.soup_kitchen_outlined, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: busy || !fulfillmentPaymentAllowed
                    ? null
                    : () => _act(order, 'prepare'),
                label: const Text('Start preparation'),
              ),
            ),

          if (status == 'accepted' && !fulfillmentPaymentAllowed)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'UPI payment must remain verified before preparation.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AbashyakaColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          if (status == 'preparing')
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: busy || !fulfillmentPaymentAllowed
                    ? null
                    : () => _act(order, 'ready'),
                label: const Text('Mark ready for pickup'),
              ),
            ),

          if (status == 'ready_for_pickup' && dispatch != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Delivery progress: ${(dispatch['execution_state'] as String? ?? 'assigned').replaceAll('_', ' ')}${(dispatch['rider_name'] as String? ?? '').isNotEmpty ? ' · ${dispatch['rider_name']}' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondaryText,
                ),
              ),
            ),
            if (dispatch['execution_state'] == 'at_pickup' &&
                dispatch['rider_assigned'] == true) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey('issue_pickup_code_${order['id']}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: busy || confirmingPickup
                      ? null
                      : () => _issuePickupCode(order),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(
                    busy
                        ? 'Issuing…'
                        : confirmingPickup
                        ? 'Confirming…'
                        : 'Issue pickup code',
                  ),
                ),
              ),
            ],
          ],

          if (busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.emerald),
              ),
            ),

          if (status == 'rejected' && order['status_events'] is List) ...[
            for (final event
                in (order['status_events'] as List<dynamic>)
                    .cast<Map<String, dynamic>>())
              if (event['event_kind'] == 'partner_rejected' &&
                  (event['reason'] as String? ?? '').isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Recorded reason: ${event['reason']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AbashyakaColors.error,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'placed' => 'Awaiting response',
    'accepted' => 'Accepted',
    'preparing' => 'Preparing',
    'ready_for_pickup' => 'Ready for pickup',
    'delivered' => 'Delivered',
    'rejected' => 'Rejected',
    'cancelled' => 'Cancelled by customer',
    _ => status.replaceAll('_', ' '),
  };

  Widget _orderTimeline(List<Map<String, dynamic>> events, String status) {
    final localizations = MaterialLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: AbashyakaColors.iceAquaWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AbashyakaColors.aquaSilverBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order timeline',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          for (final (index, event) in events.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    index == events.length - 1 && event['status'] == status
                        ? Icons.radio_button_checked
                        : Icons.history,
                    size: 16,
                    color: AbashyakaColors.signatureTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_statusLabel(event['status'] as String)),
                        if (DateTime.tryParse(
                              event['created_at']?.toString() ?? '',
                            )
                            case final DateTime timestamp)
                          Text(
                            '${localizations.formatShortDate(timestamp.toLocal())} · '
                            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(timestamp.toLocal()))}',
                            style: const TextStyle(
                              color: AbashyakaColors.secondaryText,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String status, String label) {
    Color bg;
    Color fg;
    switch (status) {
      case 'placed':
        bg = AbashyakaColors.warningSurface;
        fg = AbashyakaColors.warning;
        break;
      case 'accepted':
      case 'preparing':
        bg = AbashyakaColors.informationSurface;
        fg = AbashyakaColors.information;
        break;
      case 'ready_for_pickup':
        bg = AbashyakaColors.verifiedSurface;
        fg = AbashyakaColors.success;
        break;
      case 'delivered':
        bg = AbashyakaColors.successSurface;
        fg = AbashyakaColors.success;
        break;
      case 'rejected':
      case 'cancelled':
        bg = AbashyakaColors.errorSurface;
        fg = AbashyakaColors.error;
        break;
      default:
        bg = AbashyakaColors.unavailableSurface;
        fg = AppTheme.secondaryText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  void _showKitchenTicketModal(Map<String, dynamic> order) {
    final reference = order['reference_code'] as String? ?? 'Platform order';
    final items = (order['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final vertical = order['vertical'] == 'grocery' ? 'Grocery' : 'Food';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AbashyakaColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AbashyakaColors.verifiedSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.receipt_long,
                    color: AppTheme.emerald,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'KITCHEN TICKET',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: AppTheme.mainText,
                        ),
                      ),
                      Text(
                        '$vertical · $reference',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: AppTheme.secondaryText,
                ),
                const SizedBox(width: 6),
                Text(
                  '${order['delivery_locality'] ?? ''}, ${order['delivery_district'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'ORDER ITEMS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.secondaryText,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AbashyakaColors.pearlWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AbashyakaColors.aquaSilverBorder),
              ),
              child: Column(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.verifiedSurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '× ${item['quantity']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppTheme.emerald,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item['product_name'] as String? ?? 'Item',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if ((order['special_instructions'] as String? ?? '')
                .isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'SPECIAL NOTES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AbashyakaColors.warningSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AbashyakaColors.warningSurface),
                ),
                child: Text(
                  order['special_instructions'],
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AbashyakaColors.warning,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Back to Orders'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _paymentLabel(Map<String, dynamic> order) {
    final method = order['payment_method']?.toString() ?? '';
    if (method == 'cash_on_delivery') return 'Cash on Delivery';
    if (method == 'upi') return 'Sandbox UPI';
    return 'Payment status';
  }

  String _paymentDetail(Map<String, dynamic> order) {
    final method = order['payment_method']?.toString() ?? '';
    final status = order['payment_status']?.toString() ?? 'not_collected';
    if (method == 'cash_on_delivery') {
      final cod = order['cod_collection_state']?.toString() ?? 'due';
      return cod == 'collected'
          ? 'Synthetic COD collected at verified customer handover.'
          : 'Synthetic QA · amount due at delivery; not collected yet.';
    }
    if (method == 'upi') {
      return status == 'paid'
          ? 'Payment verified by Abashyaka backend.'
          : 'Payment is not verified; fulfillment actions are blocked.';
    }
    return 'Payment details are unavailable for this legacy order.';
  }
}

class _PickupCodeDialog extends StatefulWidget {
  const _PickupCodeDialog({
    required this.reference,
    required this.code,
    required this.expiresInSeconds,
  });

  final String reference;
  final String code;
  final int expiresInSeconds;

  @override
  State<_PickupCodeDialog> createState() => _PickupCodeDialogState();
}

class _PickupCodeDialogState extends State<_PickupCodeDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.expiresInSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_remaining <= 1) {
        timer.cancel();
        Navigator.of(context).pop();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: const Row(
      children: [
        Icon(Icons.verified_user_outlined, color: AppTheme.emerald),
        SizedBox(width: 8),
        Text(
          'Partner-to-rider handover',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Share this code only with the assigned rider collecting ${widget.reference}.',
          style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AbashyakaColors.verifiedSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AbashyakaColors.aquaSilverBorder),
          ),
          child: SelectableText(
            widget.code,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              color: AppTheme.emerald,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.timer_outlined,
              size: 14,
              color: AppTheme.secondaryText,
            ),
            const SizedBox(width: 4),
            Text(
              'Expires in $_remaining seconds.',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryText,
              ),
            ),
          ],
        ),
      ],
    ),
    actions: [
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.emerald,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close and clear'),
      ),
    ],
  );
}
