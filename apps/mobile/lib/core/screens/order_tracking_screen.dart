import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/network/customer_order_sse.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/cart_provider.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/screens/customer_cart_screen.dart';
import 'package:grepmind_mobile/core/screens/order_payment_card.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

@visibleForTesting
String? resolveCustomerDeliveryState(
  String? executionState,
  String? dispatchState,
) {
  if (executionState == null || executionState == 'not_started') {
    return dispatchState ?? executionState;
  }
  return executionState;
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  CustomerOrder? _order;
  bool _loading = true;
  String? _error;
  String? _deliveryDispatchState;
  String? _deliveryExecutionState;
  List<Map<String, dynamic>> _deliveryHistory = const [];
  String? _deliveryHistoryError;
  bool _riderAssigned = false;
  bool _notFound = false;
  CancelToken? _streamToken;
  Timer? _reconciliationTimer;
  Timer? _reconnectTimer;
  Completer<void>? _reconnectWait;
  bool _streamStopped = false;
  bool _liveConnected = false;
  bool _hasConnected = false;
  int _reconnectAttempt = 0;
  DateTime? _lastUpdatedAt;
  bool _refreshInFlight = false;
  bool _refreshAgain = false;
  CustomerOrderEventGate? _eventGate;
  bool _supportSubmitting = false;
  bool _reordering = false;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppUser?>(currentUserProvider, (previous, next) {
      if (previous?.id != next?.id) _onAccountChanged(next);
    });
    return _buildScreen(context);
  }

  Future<void> _loadOrder({bool silent = false}) async {
    final requestedUserId = ref.read(currentUserProvider)?.id;
    if (requestedUserId == null) return;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _notFound = false;
      });
    }
    try {
      final order = await ref
          .read(customerOrdersProvider.notifier)
          .fetchOrderById(widget.orderId);
      if (!mounted || ref.read(currentUserProvider)?.id != requestedUserId) {
        return;
      }
      setState(() {
        _order = order;
        _loading = false;
        _error = null;
        _notFound = false;
        _lastUpdatedAt = DateTime.now();
      });
      _startStatusStream();
      await _loadDispatchStatus();
    } on DioException catch (error) {
      if (!mounted || ref.read(currentUserProvider)?.id != requestedUserId) {
        return;
      }
      setState(() {
        _loading = false;
        _notFound = error.response?.statusCode == 404;
        _error = _notFound
            ? 'This order is missing or is not available to this account.'
            : 'Order details could not be loaded. Check your connection and retry.';
      });
    } catch (_) {
      if (!mounted || ref.read(currentUserProvider)?.id != requestedUserId) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Order details could not be loaded. Check your connection and retry.';
      });
    }
  }

  void _startStatusStream() {
    final userId = ref.read(currentUserProvider)?.id;
    if (_streamStopped ||
        userId == null ||
        _streamToken != null ||
        _isTerminal) {
      return;
    }
    final token = CancelToken();
    _streamToken = token;
    _eventGate = CustomerOrderEventGate(widget.orderId);
    _liveConnected = false;
    _reconciliationTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_queueServerRefresh()),
    );
    unawaited(_consumeStatusEvents(token));
  }

  bool get _isTerminal =>
      _order?.status == OrderStatus.delivered ||
      _order?.status == OrderStatus.completed ||
      _order?.status == OrderStatus.cancelled ||
      _order?.status == OrderStatus.rejected ||
      const {
        'delivered',
        'returned',
        'cancelled',
      }.contains(_deliveryExecutionState);

  Future<void> _consumeStatusEvents(CancelToken token) async {
    try {
      while (mounted && !_streamStopped && !token.isCancelled) {
        try {
          final response = await apiClient.get<ResponseBody>(
            '/events',
            queryParameters: {'order_id': widget.orderId},
            options: Options(responseType: ResponseType.stream),
            cancelToken: token,
          );
          final body = response.data;
          if (body == null) throw StateError('Empty order event stream');
          final lines = body.stream
              .timeout(const Duration(seconds: 45))
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter());
          await for (final event in parseServerSentEvents(lines)) {
            if (!mounted || _streamStopped || token.isCancelled) break;
            final gate = _eventGate;
            if (gate == null || !gate.shouldReconcile(event)) continue;
            if (event.event == 'connected') {
              _reconnectAttempt = 0;
              _hasConnected = true;
              _setLiveConnection(true);
              await _queueServerRefresh();
            } else {
              await _queueServerRefresh();
            }
            if (_isTerminal) break;
          }
          if (mounted &&
              !_streamStopped &&
              !token.isCancelled &&
              !_isTerminal) {
            throw StateError('Order event stream ended');
          }
        } catch (_) {
          if (!mounted || _streamStopped || token.isCancelled || _isTerminal) {
            break;
          }
        }
        if (!mounted || _streamStopped || token.isCancelled || _isTerminal) {
          break;
        }
        _setLiveConnection(false);
        await _queueServerRefresh();
        final seconds = 1 << _reconnectAttempt.clamp(0, 5);
        _reconnectAttempt = (_reconnectAttempt + 1).clamp(0, 5);
        final wait = Completer<void>();
        _reconnectWait = wait;
        _reconnectTimer = Timer(Duration(seconds: seconds), () {
          if (!wait.isCompleted) wait.complete();
        });
        await wait.future;
        _reconnectTimer = null;
        _reconnectWait = null;
      }
    } finally {
      if (identical(_streamToken, token)) {
        _streamToken = null;
        if (_isTerminal || _streamStopped) {
          _reconciliationTimer?.cancel();
          _reconciliationTimer = null;
        }
      }
    }
  }

  void _setLiveConnection(bool connected) {
    if (!mounted || _liveConnected == connected) return;
    setState(() => _liveConnected = connected);
  }

  Future<void> _queueServerRefresh() async {
    if (_refreshInFlight) {
      _refreshAgain = true;
      return;
    }
    _refreshInFlight = true;
    try {
      do {
        _refreshAgain = false;
        await _loadOrder(silent: true);
      } while (mounted && _refreshAgain && !_streamStopped);
    } finally {
      _refreshInFlight = false;
    }
  }

  void _stopStatusStream() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_reconnectWait?.isCompleted == false) _reconnectWait!.complete();
    _reconnectWait = null;
    _reconciliationTimer?.cancel();
    _reconciliationTimer = null;
    final token = _streamToken;
    _streamToken = null;
    _eventGate = null;
    token?.cancel('Order tracking identity or screen changed');
    if (mounted && _liveConnected) setState(() => _liveConnected = false);
  }

  void _onAccountChanged(AppUser? user) {
    _stopStatusStream();
    if (!mounted) return;
    setState(() {
      _order = null;
      _deliveryDispatchState = null;
      _deliveryExecutionState = null;
      _deliveryHistory = const [];
      _deliveryHistoryError = null;
      _riderAssigned = false;
      _hasConnected = false;
      _reconnectAttempt = 0;
      _error = user == null ? 'Sign in to view this order.' : null;
      _loading = user != null;
      _lastUpdatedAt = null;
    });
    if (user != null) unawaited(_loadOrder());
  }

  Future<void> _loadDispatchStatus() async {
    final order = _order;
    if (order == null || order.orderSource != 'platform_catalog') return;
    try {
      final response = await apiClient.get(
        '/orders/${Uri.encodeComponent(widget.orderId)}/delivery-status',
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _deliveryDispatchState = data['delivery_state']?.toString();
          _deliveryExecutionState = data['execution_state']?.toString();
          _riderAssigned = data['rider_assigned'] == true;
        });
      }
      final historyResponse = await apiClient.get(
        '/orders/${Uri.encodeComponent(widget.orderId)}/delivery-history',
      );
      final historyData =
          (historyResponse.data as Map<String, dynamic>)['data']
              as List<dynamic>? ??
          const [];
      if (mounted) {
        setState(() {
          _deliveryHistory = historyData
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          _deliveryHistoryError = null;
          _lastUpdatedAt = DateTime.now();
        });
        if (_isTerminal) _stopStatusStream();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _deliveryHistoryError = 'Order history is temporarily unavailable. The latest confirmed status is shown; it will retry automatically.',
        );
      }
    }
  }

  Future<void> _showDeliveryCode() async {
    try {
      final response = await apiClient.post(
        '/orders/${Uri.encodeComponent(widget.orderId)}/delivery-code',
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Your delivery code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Share this code with the assigned rider only when your order is physically handed to you.',
              ),
              const SizedBox(height: 16),
              SelectableText(
                data['delivery_code']?.toString() ?? '',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 5,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text('Expires in ${data['expires_in_seconds'] ?? 0} seconds.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      final message = error.response?.statusCode == 429
          ? 'A code was recently requested. Wait briefly before requesting another.'
          : 'Delivery code is available after the rider starts the delivery.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not request a delivery code. Check your connection and retry.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _streamStopped = true;
    _reconciliationTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_reconnectWait?.isCompleted == false) _reconnectWait!.complete();
    _streamToken?.cancel('Order detail screen disposed');
    super.dispose();
  }

  Widget _buildScreen(BuildContext context) {
    if (_loading && _order == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order details')),
        body: _LoadFailure(
          notFound: _notFound,
          message: _error ?? 'Order details could not be loaded.',
          onRetry: () => _loadOrder(),
        ),
      );
    }
    final order = _order!;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Order details'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _loadOrder(),
            tooltip: 'Refresh order',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadOrder(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            if (_error != null) _InlineError(message: _error!),
            _SummaryCard(order: order),
            if (_deliveryDispatchState != null)
              _DispatchStatusCard(
                state: _deliveryDispatchState!,
                riderAssigned: _riderAssigned,
                executionState: _deliveryExecutionState,
              ),
            if ((order.orderType == OrderType.foodDelivery ||
                    order.orderType == OrderType.platformOrder) &&
                order.isDelivery)
              _DeliveryTruthCard(order: order),
            if (order.orderSource == 'platform_catalog' &&
                order.isDelivery) ...[
              _LiveConnectionCard(
                connected: _liveConnected,
                hasConnected: _hasConnected,
                lastUpdatedAt: _lastUpdatedAt,
                terminal: _isTerminal,
              ),
              _UnifiedOrderTimeline(
                order: order,
                state: resolveCustomerDeliveryState(
                  _deliveryExecutionState,
                  _deliveryDispatchState,
                ),
                events: _deliveryHistory,
                error: _deliveryHistoryError,
              ),
              if (_deliveryExecutionState == 'en_route')
                FilledButton.icon(
                  onPressed: _showDeliveryCode,
                  icon: const Icon(Icons.key_rounded),
                  label: const Text('Show delivery verification code'),
                ),
            ],
            if (order.orderSource != 'platform_catalog')
              _StatusTimeline(order: order),
            _OrderItemsCard(order: order),
            OrderPaymentCard(
              orderId: order.id,
              paymentStatus: order.paymentStatus,
              paymentMethod: order.paymentMethod,
            ),
            const SizedBox(height: 12),
            if (_canCancel(order))
              OutlinedButton.icon(
                onPressed: () => _confirmCancel(order),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel order'),
              ),
            if (order.orderType == OrderType.foodDelivery &&
                order.status != OrderStatus.cancelled)
              FilledButton.icon(
                onPressed: _reordering ? null : () => _reorder(order),
                icon: _reordering
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.replay_rounded),
                label: Text(
                  _reordering ? 'Checking catalog…' : 'Reorder available items',
                ),
              ),
            OutlinedButton.icon(
              onPressed: _supportSubmitting ? null : _showSupportForm,
              icon: const Icon(Icons.support_agent_rounded),
              label: const Text('Report an order issue'),
            ),
          ],
        ),
      ),
    );
  }

  bool _canCancel(CustomerOrder order) =>
      order.status == OrderStatus.placed ||
      order.status == OrderStatus.confirmed ||
      order.status == OrderStatus.accepted;

  Future<void> _confirmCancel(CustomerOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
          'The server will check cancellation eligibility. If eligible, reserved stock is restored once.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(customerOrdersProvider.notifier)
        .cancelOrder(order.id);
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The order could not be cancelled. Refresh to check its current status.',
          ),
        ),
      );
    } else {
      setState(() => _order = result);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Order cancelled.')));
    }
  }

  Future<void> _reorder(CustomerOrder order) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null || order.items.isEmpty) return;
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
                    : 'Your cart contains items from ${cart.businessName ?? 'another merchant'}. It will be replaced with products from ${order.businessName}.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep cart'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace cart'),
                ),
              ],
            ),
          ) ??
          false;
      if (!replace) return;
    }
    setState(() => _reordering = true);
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
    if (!mounted) return;
    setState(() => _reordering = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
    if (result.ready) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const CustomerCartScreen()));
    }
  }

  Future<void> _showSupportForm() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report an order issue'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText: 'Describe what went wrong',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    if (reason.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide at least 10 characters.')),
      );
      return;
    }
    setState(() => _supportSubmitting = true);
    final ok = await ref
        .read(customerOrdersProvider.notifier)
        .submitSupportReport(widget.orderId, reason);
    if (!mounted) return;
    setState(() => _supportSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Your report was sent to the support queue.'
              : 'Could not submit the report. Retry later.',
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.order});
  final CustomerOrder order;
  @override
  Widget build(BuildContext context) {
    final kind = switch (order.orderType) {
      OrderType.foodDelivery =>
        order.isDelivery ? 'Food delivery' : 'Food takeaway',
      OrderType.platformOrder =>
        order.platformVertical == 'grocery'
            ? 'Grocery delivery'
            : 'Grepmind Food delivery',
      OrderType.tableReservation => 'Table reservation',
      OrderType.hotelBooking => 'Hotel stay',
      OrderType.serviceBooking => 'Service booking',
    };
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            order.statusDisplay,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            order.businessName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text('$kind · ${order.createdAt.toLocal()}'),
          const SizedBox(height: 5),
          Text(
            'Reference ${order.voucherCode}',
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
        ],
      ),
    );
  }
}

class _DeliveryTruthCard extends StatelessWidget {
  const _DeliveryTruthCard({required this.order});
  final CustomerOrder order;
  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery updates',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          order.etaMinutes > 0
              ? 'Merchant estimate: ${order.etaMinutes} minutes'
              : 'Delivery estimate is not available.',
        ),
        const SizedBox(height: 6),
        const Text(
          'Live rider location is not available for this order.',
          style: TextStyle(color: AppTheme.secondaryText),
        ),
        if (order.deliveryAddress?.isNotEmpty == true) ...[
          const Divider(height: 20),
          const Text(
            'Delivery address',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(order.deliveryAddress!),
        ],
      ],
    ),
  );
}

class _DispatchStatusCard extends StatelessWidget {
  const _DispatchStatusCard({
    required this.state,
    required this.riderAssigned,
    required this.executionState,
  });
  final String state;
  final bool riderAssigned;
  final String? executionState;
  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.delivery_dining_outlined, color: AppTheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Delivery dispatch',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                customerDeliveryDispatchMessage(
                  state: state,
                  riderAssigned: riderAssigned,
                  executionState: executionState,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Rider location and delivery time are not available yet.',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LiveConnectionCard extends StatelessWidget {
  const _LiveConnectionCard({
    required this.connected,
    required this.hasConnected,
    required this.lastUpdatedAt,
    required this.terminal,
  });
  final bool connected;
  final bool hasConnected;
  final DateTime? lastUpdatedAt;
  final bool terminal;

  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      children: [
        Icon(
          connected
              ? Icons.wifi_rounded
              : terminal
              ? Icons.check_circle_outline_rounded
              : Icons.sync_rounded,
          color: connected || terminal
              ? const Color(0xFF138A53)
              : AppTheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connected
                    ? 'Live order updates connected'
                    : terminal
                    ? 'Order updates complete'
                    : hasConnected
                    ? 'Reconnecting to live updates'
                    : 'Connecting to live order updates',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (lastUpdatedAt != null)
                Text(
                  'Last checked ${TimeOfDay.fromDateTime(lastUpdatedAt!.toLocal()).format(context)}',
                  style: const TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

@visibleForTesting
String formatOrderTrackingTimestamp(DateTime value) =>
    DateFormat('d MMM, h:mm a').format(value.toLocal());

@visibleForTesting
String customerDeliveryDispatchMessage({
  required String state,
  required bool riderAssigned,
  required String? executionState,
}) {
  if (executionState == 'delivered') {
    return 'Delivery completed. The rider assignment is closed.';
  }
  if (riderAssigned) return 'A rider has been assigned to your order.';
  return switch (state) {
    'pending_dispatch' ||
    'offered' => 'Grepmind is finding an approved rider for this locality.',
    'no_rider_available' =>
      'A rider is not available yet. Grepmind will retry when possible.',
    'not_dispatched' || 'not_started' =>
      'Rider dispatch begins when the partner starts preparing your order.',
    'cancelled' => 'Delivery dispatch was cancelled with this order.',
    _ => 'Dispatch status is being updated.',
  };
}

class _UnifiedOrderTimeline extends StatelessWidget {
  const _UnifiedOrderTimeline({
    required this.order,
    required this.state,
    required this.events,
    required this.error,
  });
  final CustomerOrder order;
  final String? state;
  final List<Map<String, dynamic>> events;
  final String? error;

  static const _deliveryLabels = <String, String>{
    'pending_dispatch': 'Finding an available rider',
    'offered': 'Rider offer sent',
    'no_rider_available': 'No rider available yet',
    'placed': 'Order placed',
    'accepted': 'Partner accepted',
    'preparing': 'Partner is preparing',
    'ready_for_pickup': 'Ready for pickup',
    'assigned': 'Rider assigned',
    'rider_assigned': 'Rider assigned',
    'arriving_at_pickup': 'Rider heading to partner',
    'at_pickup': 'Rider arrived at partner',
    'pickup_verified': 'Partner handover verified',
    'picked_up': 'Order picked up',
    'en_route': 'On the way to you',
    'customer_otp_verified': 'Delivered with your confirmation',
    'delivered': 'Delivered',
    'pickup_failed': 'Pickup issue reported',
    'customer_unreachable': 'Rider could not reach you',
    'delivery_failed': 'Delivery issue reported',
    'return_required': 'Return requested',
    'return_in_progress': 'Returning to partner',
    'returned': 'Returned to partner',
    'cancelled': 'Delivery cancelled',
    'resolved': 'Delivery issue resolved',
  };

  List<_TimelineEntry> _entries() {
    final result = <_TimelineEntry>[
      for (final event in events)
        _TimelineEntry(
          title: _timelineLabel(event),
          at:
              DateTime.tryParse(event['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return result;
  }

  String _timelineLabel(Map<String, dynamic> event) {
    final eventType = event['event_type']?.toString();
    final state = event['to_state']?.toString();
    if (eventType == 'order_status') {
      return _deliveryLabels[state] ?? 'Order updated';
    }
    return _deliveryLabels[eventType] ??
        _deliveryLabels[state] ??
        (eventType?.replaceAll('_', ' ') ?? 'Delivery update');
  }

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order and delivery timeline',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.deepOrange),
            ),
          ),
        if (_entries().isEmpty && error == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Order updates will appear here as the partner and rider progress.',
            ),
          ),
        for (final event in _entries())
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(
              Icons.check_circle_outline_rounded,
              color: AppTheme.primary,
            ),
            title: Text(
              event.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(formatOrderTrackingTimestamp(event.at)),
          ),
        if (state != null)
          Text(
            'Current delivery state · ${_deliveryLabels[state] ?? state!.replaceAll('_', ' ')}',
            style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
          ),
        const SizedBox(height: 4),
        const Text(
          'No live location or estimated arrival time is shown.',
          style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
        ),
      ],
    ),
  );
}

class _TimelineEntry {
  const _TimelineEntry({required this.title, required this.at});
  final String title;
  final DateTime at;
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.order});
  final CustomerOrder order;
  @override
  Widget build(BuildContext context) {
    final events = order.statusEvents;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status history',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (events.isEmpty)
            const Text('No status history is available for this order yet.'),
          for (final event in events)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                event.status == order.status
                    ? Icons.radio_button_checked
                    : Icons.check_circle_outline,
                color: event.status == order.status
                    ? AppTheme.primary
                    : const Color(0xFF138A53),
              ),
              title: Text(
                event.status.statusLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                event.eventKind == 'history_snapshot'
                    ? 'Earlier status history was not recorded for this order.'
                    : [
                        event.createdAt.toLocal().toString(),
                        if (event.reason?.isNotEmpty == true) event.reason!,
                      ].join('\n'),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderItemsCard extends StatelessWidget {
  const _OrderItemsCard({required this.order});
  final CustomerOrder order;
  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order summary',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(child: Text('${item.quantity} × ${item.name}')),
                Text('₹${item.subtotal.toStringAsFixed(2)}'),
              ],
            ),
          ),
        const Divider(),
        _MoneyRow(label: 'Items', value: order.itemTotal),
        _MoneyRow(label: 'Delivery', value: order.deliveryFee),
        _MoneyRow(label: 'Tax', value: order.tax),
        const Divider(),
        _MoneyRow(label: 'Total', value: order.grandTotal, bold: true),
      ],
    ),
  );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.bold = false,
  });
  final String label;
  final double value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
          ),
        ),
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFD8E2F1)),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({
    required this.notFound,
    required this.message,
    required this.onRetry,
  });
  final bool notFound;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            notFound ? Icons.receipt_long_outlined : Icons.cloud_off_outlined,
            size: 48,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            notFound ? 'Order not found' : 'Could not load order',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (!notFound) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(message, style: const TextStyle(color: Color(0xFF9A3412))),
  );
}

extension on OrderStatus {
  String get statusLabel => switch (this) {
    OrderStatus.placed => 'Order placed',
    OrderStatus.accepted => 'Accepted by partner',
    OrderStatus.confirmed => 'Accepted',
    OrderStatus.preparing => 'Preparing',
    OrderStatus.readyForPickup => 'Ready for pickup',
    OrderStatus.rejected => 'Partner unable to accept',
    OrderStatus.outForDelivery => 'Out for delivery',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.completed => 'Completed',
    OrderStatus.cancelled => 'Cancelled',
  };
}
