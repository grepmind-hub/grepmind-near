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
import 'package:grepmind_mobile/core/widgets/category_placeholder.dart';

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

  bool get _usesDeliveryTracking {
    final order = _order;
    return order != null &&
        order.isDelivery &&
        (order.orderSource == 'platform_catalog' ||
            order.orderSource == 'merchant_catalog');
  }

  Future<void> _loadDispatchStatus() async {
    final order = _order;
    if (!_usesDeliveryTracking) return;
    final customerId = ref.read(currentUserProvider)?.id;
    bool isCurrentRequest() =>
        mounted &&
        identical(_order, order) &&
        ref.read(currentUserProvider)?.id == customerId;
    try {
      final response = await apiClient.get(
        '/orders/${Uri.encodeComponent(widget.orderId)}/delivery-status',
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      if (!isCurrentRequest()) return;
      setState(() {
        _deliveryDispatchState = data['delivery_state']?.toString();
        _deliveryExecutionState = data['execution_state']?.toString();
        _riderAssigned = data['rider_assigned'] == true;
      });
      final historyResponse = await apiClient.get(
        '/orders/${Uri.encodeComponent(widget.orderId)}/delivery-history',
      );
      final historyData =
          (historyResponse.data as Map<String, dynamic>)['data']
              as List<dynamic>? ??
          const [];
      if (isCurrentRequest()) {
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
      if (isCurrentRequest()) {
        setState(
          () => _deliveryHistoryError = 'Order history is temporarily unavailable. The latest confirmed status is shown; it will retry automatically.',
        );
      }
    }
  }

  Future<void> _showDeliveryCode() async {
    final customerId = ref.read(currentUserProvider)?.id;
    if (customerId == null ||
        !_usesDeliveryTracking ||
        _isTerminal ||
        _deliveryExecutionState != 'en_route') {
      return;
    }
    try {
      final response = await apiClient.post(
        '/orders/${Uri.encodeComponent(widget.orderId)}/delivery-code',
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      if (!mounted ||
          ref.read(currentUserProvider)?.id != customerId ||
          _isTerminal ||
          _deliveryExecutionState != 'en_route') {
        return;
      }
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
                  color: AppTheme.emerald,
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
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text('Order details'),
        elevation: 0,
        backgroundColor: AbashyakaColors.pureWhite,
        foregroundColor: AbashyakaColors.primaryText,
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
            if (_usesDeliveryTracking) ...[
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
              if (!_isTerminal && _deliveryExecutionState == 'en_route') ...[
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: _showDeliveryCode,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    foregroundColor: AbashyakaColors.pureWhite,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text(
                    'Show delivery verification code',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
            if (!_usesDeliveryTracking) _StatusTimeline(order: order),
            _OrderItemsCard(order: order),
            OrderPaymentCard(
              orderId: order.id,
              paymentStatus: order.paymentStatus,
              paymentMethod: order.paymentMethod,
            ),
            const SizedBox(height: 12),
            if (_canCancel(order)) ...[
              OutlinedButton.icon(
                onPressed: () => _confirmCancel(order),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AbashyakaColors.error,
                  side: const BorderSide(color: Color(0xFFFECACA)),
                  backgroundColor: const Color(0xFFFEF2F2),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text(
                  'Cancel order',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (order.orderType == OrderType.foodDelivery &&
                order.status != OrderStatus.cancelled) ...[
              FilledButton.icon(
                onPressed: _reordering ? null : () => _reorder(order),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  foregroundColor: AbashyakaColors.pureWhite,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _reordering
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AbashyakaColors.pureWhite,
                        ),
                      )
                    : const Icon(Icons.replay_rounded, size: 18),
                label: Text(
                  _reordering ? 'Checking catalog…' : 'Reorder available items',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: _supportSubmitting ? null : _showSupportForm,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF334155),
                side: const BorderSide(color: AbashyakaColors.aquaSilverBorder),
                backgroundColor: AbashyakaColors.pureWhite,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.support_agent_rounded, size: 18),
              label: const Text(
                'Report an order issue',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
            : 'Abashyaka Food delivery',
      OrderType.tableReservation => 'Table reservation',
      OrderType.hotelBooking => 'Hotel stay',
      OrderType.serviceBooking => 'Service booking',
    };
    final formattedDate = DateFormat('d MMM yyyy, h:mm a')
        .format(order.createdAt.toLocal());

    final (
      statusBg,
      statusBorder,
      statusColor,
      statusIcon,
    ) = switch (order.status) {
      OrderStatus.delivered || OrderStatus.completed => (
        AbashyakaColors.successSurface,
        AppTheme.emerald.withValues(alpha: 0.25),
        AppTheme.emeraldDark,
        Icons.check_circle_rounded,
      ),
      OrderStatus.cancelled || OrderStatus.rejected => (
        const Color(0xFFFEF2F2),
        const Color(0xFFFECACA),
        const Color(0xFFB91C1C),
        Icons.cancel_rounded,
      ),
      OrderStatus.readyForPickup ||
      OrderStatus.preparing ||
      OrderStatus.accepted => (
        const Color(0xFFFFF7ED),
        const Color(0xFFFED7AA),
        const Color(0xFFFF8A00),
        Icons.schedule_rounded,
      ),
      _ => (
        AbashyakaColors.successSurface,
        AppTheme.emerald.withValues(alpha: 0.25),
        AppTheme.emerald,
        Icons.receipt_rounded,
      ),
    };

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 48,
                  height: 48,
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
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AbashyakaColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$kind · $formattedDate',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                        fontWeight: FontWeight.w500,
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 5),
                    Text(
                      order.statusDisplay,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (order.voucherCode?.isNotEmpty == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AbashyakaColors.unavailableSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AbashyakaColors.softGrey),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.tag_rounded,
                        size: 13,
                        color: AppTheme.secondaryText,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        order.voucherCode!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
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
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AbashyakaColors.successSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.emerald.withValues(alpha: 0.25),
                ),
              ),
              child: const Icon(
                Icons.update_rounded,
                color: AppTheme.emerald,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Delivery updates',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AbashyakaColors.primaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          order.etaMinutes > 0
              ? 'Merchant estimate: ${order.etaMinutes} minutes'
              : 'Delivery estimate is not available.',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AbashyakaColors.primaryText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Live rider location is not available for this order.',
          style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
        ),
        if (order.deliveryAddress?.isNotEmpty == true) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AbashyakaColors.softGrey),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AbashyakaColors.successSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: AppTheme.emerald,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery address',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AbashyakaColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.deliveryAddress!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF475569),
                        height: 1.35,
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
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AbashyakaColors.successSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: const Icon(
            Icons.delivery_dining_rounded,
            color: AbashyakaColors.success,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Delivery dispatch',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AbashyakaColors.primaryText,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                customerDeliveryDispatchMessage(
                  state: state,
                  riderAssigned: riderAssigned,
                  executionState: executionState,
                ),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF334155),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Rider location and delivery time are not available yet.',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
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
  Widget build(BuildContext context) {
    final isGood = connected || terminal;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isGood ? AbashyakaColors.successSurface : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGood ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isGood ? AbashyakaColors.successSurface : AbashyakaColors.warningSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              connected
                  ? Icons.wifi_rounded
                  : terminal
                  ? Icons.check_circle_outline_rounded
                  : Icons.sync_rounded,
              size: 16,
              color: isGood ? AbashyakaColors.success : AbashyakaColors.warning,
            ),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isGood
                        ? const Color(0xFF065F46)
                        : AbashyakaColors.warning,
                  ),
                ),
                if (lastUpdatedAt != null)
                  Text(
                    'Last checked ${TimeOfDay.fromDateTime(lastUpdatedAt!.toLocal()).format(context)}',
                    style: TextStyle(
                      color: isGood
                          ? AbashyakaColors.success.withValues(alpha: 0.8)
                          : const Color(0xFFB45309),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
    'offered' => 'Abashyaka is finding an approved rider for this locality.',
    'no_rider_available' =>
      'A rider is not available yet. Abashyaka will retry when possible.',
    'not_dispatched' || 'not_started' =>
      'Rider dispatch begins when the partner starts preparing your order.',
    'cancelled' => 'Delivery dispatch was cancelled with this order.',
    _ => 'Dispatch status is being updated.',
  };
}

IconData _iconForTimelineStep(String label) {
  final l = label.toLowerCase();
  if (l.contains('placed')) return Icons.shopping_bag_outlined;
  if (l.contains('accept')) return Icons.storefront_outlined;
  if (l.contains('prepar')) return Icons.soup_kitchen_outlined;
  if (l.contains('ready') ||
      l.contains('pickup verified') ||
      l.contains('handover')) {
    return Icons.inventory_2_outlined;
  }
  if (l.contains('heading') || l.contains('arrived at partner')) {
    return Icons.store_outlined;
  }
  if (l.contains('rider') || l.contains('assign')) {
    return Icons.two_wheeler_outlined;
  }
  if (l.contains('way') || l.contains('en route') || l.contains('picked up')) {
    return Icons.delivery_dining_outlined;
  }
  if (l.contains('delivered') || l.contains('completed')) {
    return Icons.check_circle_outline_rounded;
  }
  if (l.contains('issue') ||
      l.contains('cancel') ||
      l.contains('fail') ||
      l.contains('rejected') ||
      l.contains('unreachable')) {
    return Icons.error_outline_rounded;
  }
  return Icons.check_rounded;
}

class _TimelineStepItem extends StatelessWidget {
  const _TimelineStepItem({
    required this.title,
    required this.subtitle,
    this.detail,
    required this.isFirst,
    required this.isLast,
    required this.isCompleted,
    required this.isActive,
    this.icon,
  });

  final String title;
  final String subtitle;
  final String? detail;
  final bool isFirst;
  final bool isLast;
  final bool isCompleted;
  final bool isActive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vertical connector line and circular node
          SizedBox(
            width: 32,
            child: Column(
              children: [
                // Top line
                Container(
                  width: 2.5,
                  height: 6,
                  color: isFirst
                      ? Colors.transparent
                      : (isCompleted || isActive
                            ? AbashyakaColors.success
                            : AbashyakaColors.softGrey),
                ),
                // Indicator Node
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AbashyakaColors.success
                        : isCompleted
                        ? AbashyakaColors.successSurface
                        : AbashyakaColors.pearlWhite,
                    border: Border.all(
                      color: isActive
                          ? AbashyakaColors.success
                          : isCompleted
                          ? AbashyakaColors.success
                          : AbashyakaColors.aquaSilverBorder,
                      width: isActive ? 2.5 : 1.5,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AbashyakaColors.success
                                  .withValues(alpha: 0.3),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Icon(
                      icon ??
                          (isCompleted || isActive
                              ? Icons.check_rounded
                              : Icons.circle),
                      size: icon != null
                          ? 13
                          : (isCompleted || isActive ? 14 : 6),
                      color: isActive
                          ? AbashyakaColors.pureWhite
                          : isCompleted
                          ? AbashyakaColors.success
                          : AbashyakaColors.disabledText,
                    ),
                  ),
                ),
                // Bottom connecting vertical line
                Expanded(
                  child: isLast
                      ? const SizedBox.shrink()
                      : Container(
                          width: 2.5,
                          color: isCompleted
                              ? AbashyakaColors.success
                              : AbashyakaColors.softGrey,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isActive
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: isActive
                                ? const Color(0xFF065F46)
                                : AbashyakaColors.primaryText,
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AbashyakaColors.successSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AbashyakaColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AbashyakaColors.mutedText,
                    ),
                  ),
                  if (detail != null && detail!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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

  bool get _isOrderTerminal =>
      order.status == OrderStatus.delivered ||
      order.status == OrderStatus.completed ||
      order.status == OrderStatus.cancelled ||
      order.status == OrderStatus.rejected;

  @override
  Widget build(BuildContext context) {
    final timelineEntries = _entries();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AbashyakaColors.successSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Icon(
                  Icons.alt_route_rounded,
                  size: 18,
                  color: AbashyakaColors.success,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Order and delivery timeline',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AbashyakaColors.primaryText,
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          if (timelineEntries.isEmpty && error == null)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Order updates will appear here as the partner and rider progress.',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
              ),
            )
          else ...[
            const SizedBox(height: 14),
            for (var i = 0; i < timelineEntries.length; i++)
              _TimelineStepItem(
                title: timelineEntries[i].title,
                subtitle: formatOrderTrackingTimestamp(timelineEntries[i].at),
                isFirst: i == 0,
                isLast: i == timelineEntries.length - 1,
                isCompleted: i < timelineEntries.length - 1 || _isOrderTerminal,
                isActive: i == timelineEntries.length - 1 && !_isOrderTerminal,
                icon: _iconForTimelineStep(timelineEntries[i].title),
              ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AbashyakaColors.pearlWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AbashyakaColors.softGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state != null) ...[
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AbashyakaColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Current delivery state · ${_deliveryLabels[state] ?? state!.replaceAll('_', ' ')}',
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                const Text(
                  'No live location or estimated arrival time is shown.',
                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AbashyakaColors.successSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: AbashyakaColors.success,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Status history',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AbashyakaColors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (events.isEmpty)
            const Text(
              'No status history is available for this order yet.',
              style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
            )
          else
            for (var i = 0; i < events.length; i++)
              _TimelineStepItem(
                title: events[i].status.statusLabel,
                subtitle: events[i].eventKind == 'history_snapshot'
                    ? 'Earlier status history was not recorded for this order.'
                    : formatOrderTrackingTimestamp(events[i].createdAt),
                detail: events[i].reason?.isNotEmpty == true
                    ? events[i].reason
                    : null,
                isFirst: i == 0,
                isLast: i == events.length - 1,
                isCompleted:
                    i < events.length - 1 ||
                    events[i].status == OrderStatus.delivered,
                isActive:
                    i == events.length - 1 &&
                    events[i].status != OrderStatus.delivered,
                icon: _iconForTimelineStep(events[i].status.statusLabel),
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
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AbashyakaColors.successSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 18,
                color: AbashyakaColors.success,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Order summary',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AbashyakaColors.primaryText,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AbashyakaColors.unavailableSurface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${order.items.length} ${order.items.length == 1 ? 'item' : 'items'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AbashyakaColors.mutedText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AbashyakaColors.pearlWhite,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AbashyakaColors.softGrey),
                  ),
                  child: Text(
                    '${item.quantity}×',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AbashyakaColors.primaryText,
                    ),
                  ),
                ),
                Text(
                  '₹${item.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AbashyakaColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: AbashyakaColors.softGrey),
        ),
        _MoneyRow(label: 'Items', value: order.itemTotal),
        _MoneyRow(label: 'Delivery', value: order.deliveryFee),
        _MoneyRow(label: 'Tax', value: order.tax),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: AbashyakaColors.softGrey),
        ),
        _MoneyRow(
          label: 'Total',
          value: order.grandTotal,
          bold: true,
          highlight: true,
        ),
      ],
    ),
  );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.highlight = false,
  });
  final String label;
  final double value;
  final bool bold;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: highlight ? 15 : 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            color: highlight
                ? AbashyakaColors.primaryText
                : const Color(0xFF475569),
          ),
        ),
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: highlight ? 16 : 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            color: highlight
                ? AbashyakaColors.success
                : AbashyakaColors.primaryText,
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: AbashyakaColors.pureWhite,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.brandBorder, width: 1.2),
      boxShadow: [
        BoxShadow(
          color: AbashyakaColors.primaryText.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
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
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.emerald,
                foregroundColor: AbashyakaColors.pureWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
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
