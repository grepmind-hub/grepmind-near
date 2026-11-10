import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class MerchantPlatformOrdersScreen extends ConsumerStatefulWidget {
  const MerchantPlatformOrdersScreen({super.key});

  @override
  ConsumerState<MerchantPlatformOrdersScreen> createState() =>
      _MerchantPlatformOrdersScreenState();
}

class _MerchantPlatformOrdersScreenState
    extends ConsumerState<MerchantPlatformOrdersScreen> {
  String? _businessId;
  String? _error;
  bool _loading = true;
  String? _busyOrder;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
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
    } catch (error) {
      if (mounted) setState(() => _error = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Partner Orders'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            tooltip: 'Refresh orders',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              color: AppTheme.primaryContainer,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Orders assigned by Grepmind appear here. Customer prices stay platform-controlled. Payment is not collected, and marking ready does not mean delivered.',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_loading && _orders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && _error == null && _orders.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 52,
                      color: AppTheme.primary,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No assigned platform orders',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'New orders will appear after Grepmind assigns your business to fulfill the complete basket.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            for (final order in _orders) _orderCard(order),
          ],
        ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? 'placed';
    final items = (order['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final busy = _busyOrder == order['id'];
    final vertical = order['vertical'] == 'grocery'
        ? 'Grocery order'
        : 'Food order';
    final statusLabel = switch (status) {
      'placed' => 'Awaiting response',
      'accepted' => 'Accepted',
      'preparing' => 'Preparing',
      'ready_for_pickup' => 'Ready for pickup',
      'rejected' => 'Rejected',
      'cancelled' => 'Cancelled by customer',
      _ => status,
    };
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
        title: Text(
          vertical,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${order['reference_code'] ?? 'Platform order'} · ${order['delivery_locality'] ?? ''}, ${order['delivery_district'] ?? ''}\n$statusLabel',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          for (final item in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item['product_name'] as String? ?? 'Product'),
              subtitle: Text(
                '${item['variant_name'] ?? ''} · ${item['unit_label'] ?? ''}',
              ),
              trailing: Text(
                '× ${item['quantity']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          if ((order['special_instructions'] as String? ?? '').isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Instructions: ${order['special_instructions']}',
                  style: const TextStyle(color: AppTheme.secondaryText),
                ),
              ),
            ),
          if (status == 'placed')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _reject(order),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => _act(order, 'accept'),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          if (status == 'accepted')
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : () => _act(order, 'prepare'),
                child: const Text('Start preparation'),
              ),
            ),
          if (status == 'preparing')
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : () => _act(order, 'ready'),
                child: const Text('Mark ready for pickup'),
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
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
                    child: Text('Recorded reason: ${event['reason']}'),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
