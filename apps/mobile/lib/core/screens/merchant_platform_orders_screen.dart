import 'dart:async';

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
    extends ConsumerState<MerchantPlatformOrdersScreen>
    with WidgetsBindingObserver {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dispatchRefreshTimer?.cancel();
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

    // Lock before opening the confirmation dialog so rapid taps cannot queue
    // multiple code issuances for the same order.
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
      // The code is kept only in this local stack frame and dialog; never log or persist it.
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
              backgroundColor: AppTheme.coral,
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
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.merchantCoralLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.merchantCoralBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: AppTheme.coral,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Partner Fulfillment Orders',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Fulfill catalog orders, verify payment & issue pickup codes.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
            if (_dispatchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_dispatchError!),
                  ),
                ),
              ),
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
                      color: AppTheme.coral,
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
    final paymentMethod = order['payment_method']?.toString() ?? '';
    final paymentStatus =
        order['payment_status']?.toString() ?? 'not_collected';
    final codState =
        order['cod_collection_state']?.toString() ?? 'not_applicable';
    final fulfillmentPaymentAllowed = switch (paymentMethod) {
      'upi' => paymentStatus == 'paid',
      'cash_on_delivery' => codState == 'due' || codState == 'collected',
      _ => true, // Existing legacy orders retain their established workflow.
    };
    final items = (order['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final busy = _busyOrder == order['id'];
    final confirmingPickup = _confirmingPickupOrder == order['id'];
    final dispatch = _dispatchByOrder[order['id']];
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
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.payments_outlined),
            title: Text(_paymentLabel(order)),
            subtitle: Text(_paymentDetail(order)),
          ),
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
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.coral,
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
                ),
              ),
            ),
          if (status == 'accepted')
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.coral,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: busy || !fulfillmentPaymentAllowed
                    ? null
                    : () => _act(order, 'prepare'),
                child: const Text('Start preparation'),
              ),
            ),
          if (status == 'accepted' && !fulfillmentPaymentAllowed)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'UPI payment must remain verified before preparation.',
                ),
              ),
            ),
          if (status == 'preparing')
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.coral,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: busy || !fulfillmentPaymentAllowed
                    ? null
                    : () => _act(order, 'ready'),
                child: const Text('Mark ready for pickup'),
              ),
            ),
          if (status == 'ready_for_pickup' && dispatch != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Delivery progress: ${(dispatch['execution_state'] as String? ?? 'assigned').replaceAll('_', ' ')}${(dispatch['rider_name'] as String? ?? '').isNotEmpty ? ' · ${dispatch['rider_name']}' : ''}',
                style: const TextStyle(color: AppTheme.secondaryText),
              ),
            ),
            if (dispatch['execution_state'] == 'at_pickup' &&
                dispatch['rider_assigned'] == true)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey('issue_pickup_code_${order['id']}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.coral,
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
          ? 'Payment verified by Grepmind backend.'
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
    title: const Text('Partner-to-rider handover'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Share this code only with the assigned rider collecting ${widget.reference}.',
        ),
        const SizedBox(height: 18),
        SelectableText(
          widget.code,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
            color: AppTheme.coral,
          ),
        ),
        const SizedBox(height: 12),
        Text('Expires in $_remaining seconds.'),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close and clear'),
      ),
    ],
  );
}
