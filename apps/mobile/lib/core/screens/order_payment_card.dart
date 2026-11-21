import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/cod_cash_provider.dart';
import 'package:grepmind_mobile/core/providers/payment_workflow_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class OrderPaymentCard extends ConsumerWidget {
  const OrderPaymentCard({
    super.key,
    required this.orderId,
    required this.paymentStatus,
    this.paymentMethod,
  });
  final String orderId;
  final String paymentStatus;
  final String? paymentMethod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (paymentMethod == 'cash_on_delivery') {
      return _CODStatusCard(orderId: orderId, paymentStatus: paymentStatus);
    }
    final userId = ref.watch(currentUserProvider)?.id;
    if (userId == null) return _legacyCard(paymentStatus);
    final key = (orderId: orderId, userId: userId);
    final state = ref.watch(paymentWorkflowProvider(key));
    final notifier = ref.read(paymentWorkflowProvider(key).notifier);
    final data = state.data;
    final status = data['payment_status']?.toString() ?? paymentStatus;
    final amount = data['amount_minor'] is num
        ? (data['amount_minor'] as num).toInt()
        : 0;
    final refundable = data['refundable_amount_minor'] is num
        ? (data['refundable_amount_minor'] as num).toInt()
        : 0;
    final attempt = data['latest_attempt_status']?.toString() ?? '';
    final refunds = data['refunds'] is List
        ? (data['refunds'] as List).whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, color: AppTheme.emerald),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Payment',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                IconButton(
                  onPressed: state.isLoading ? null : notifier.load,
                  tooltip: 'Refresh payment status',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'SANDBOX PAYMENT — No real money will be charged.',
                style: TextStyle(
                  color: AppTheme.emeraldDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (state.isLoading && data.isEmpty)
              const LinearProgressIndicator()
            else ...[
              _line('Order reference', orderId),
              _line('Amount payable', _money(amount)),
              _line(
                'Payment method',
                paymentMethod == 'upi' ? 'Sandbox UPI' : 'Abashyaka sandbox',
              ),
              _line('Payment status', _paymentLabel(status, attempt)),
              if (data.isNotEmpty &&
                  data['eligible'] != true &&
                  status != 'paid')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Payment is unavailable for this order or sandbox configuration.',
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                ),
              if (data.isEmpty && status == 'not_collected')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Payment is unavailable. No payment was collected or confirmed for this order.',
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                ),
              if (attempt == 'reconciliation_required')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Payment verification needs reconciliation. Refresh later; do not submit another payment.',
                    style: TextStyle(color: Color(0xFF9A5B00)),
                  ),
                ),
              if (data['eligible'] == true && status != 'paid') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.emerald,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed:
                        state.isBusy ||
                            attempt == 'pending' ||
                            attempt == 'session_created'
                        ? null
                        : notifier.startPayment,
                    icon: state.isBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline_rounded),
                    label: Text(
                      state.isBusy
                          ? 'Preparing sandbox session…'
                          : attempt == 'failed' || attempt == 'expired'
                          ? 'Retry sandbox payment'
                          : 'Start sandbox payment',
                    ),
                  ),
                ),
              ],
              if (kDebugMode &&
                  (attempt == 'pending' ||
                      attempt == 'session_created' ||
                      attempt == 'reconciliation_required')) ...[
                const SizedBox(height: 12),
                const Text(
                  'QA controls · backend allowlist required',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF667085),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final outcome in const [
                      ('pending', 'Pending'),
                      ('succeeded', 'Success'),
                      ('failed', 'Failure'),
                      ('expired', 'Expiry'),
                    ])
                      TextButton(
                        onPressed: state.isBusy
                            ? null
                            : () => notifier.simulatePayment(outcome.$1),
                        child: Text(outcome.$2),
                      ),
                  ],
                ),
              ],
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    state.error!,
                    style: const TextStyle(color: Color(0xFFB42318)),
                  ),
                ),
              if (status == 'paid' && refundable <= 0)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No refundable balance is currently available. Pending or unresolved refunds remain reserved until reconciled.',
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                ),
              if (status == 'paid' && refundable > 0) ...[
                const Divider(height: 24),
                Text(
                  'Request finance review — ${_money(refundable)} remaining',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Requests require finance review. This is not a promise of a bank credit.',
                  style: TextStyle(color: Color(0xFF667085)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: state.isBusy
                      ? null
                      : () => _requestRefund(context, notifier),
                  icon: const Icon(Icons.replay_circle_filled_outlined),
                  label: const Text('Request sandbox refund'),
                ),
              ],
              if (refunds.isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  'Refund history',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                for (final refund in refunds) ...[
                  const SizedBox(height: 8),
                  _line(
                    'Refund ${refund['id']?.toString().substring(0, 8) ?? ''}',
                    '${_money((refund['amount_minor'] as num?)?.toInt() ?? 0)} · ${_refundLabel(refund['status']?.toString() ?? '')}',
                  ),
                  if (kDebugMode &&
                      refund['status'] == 'processing' &&
                      refund['id'] is String)
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: state.isBusy
                              ? null
                              : () => notifier.simulateRefund(
                                  refund['id'] as String,
                                  'succeeded',
                                ),
                          child: const Text('QA success'),
                        ),
                        TextButton(
                          onPressed: state.isBusy
                              ? null
                              : () => notifier.simulateRefund(
                                  refund['id'] as String,
                                  'failed',
                                ),
                          child: const Text('QA failure'),
                        ),
                      ],
                    ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _requestRefund(
    BuildContext context,
    PaymentWorkflowNotifier notifier,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const SimpleDialog(
        title: Text('Choose a refund reason'),
        children: [
          _ReasonOption('order_cancelled', 'Order cancelled'),
          _ReasonOption('items_missing', 'Items missing'),
          _ReasonOption('items_damaged', 'Items damaged'),
          _ReasonOption('duplicate_payment', 'Duplicate payment'),
          _ReasonOption('other', 'Other'),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    final payment = notifier.paymentData;
    final amount = payment['refundable_amount_minor'] is num
        ? (payment['refundable_amount_minor'] as num).toInt()
        : 0;
    if (amount <= 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit refund review request?'),
        content: Text(
          'Request finance review for ${_money(amount)}. This sandbox request does not guarantee a bank credit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit request'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await notifier.requestRefund(reason);
    }
  }

  static Widget _legacyCard(String status) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        status == 'not_collected'
            ? 'Payment is unavailable. No payment was collected or confirmed for this order.'
            : 'Payment status: $status',
      ),
    ),
  );
  static Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF667085))),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  static String _money(int minor) =>
      '₹${(minor ~/ 100)}.${(minor % 100).toString().padLeft(2, '0')}';
  static String _paymentLabel(String payment, String attempt) {
    if (payment == 'paid') return 'Verified paid';
    if (attempt == 'reconciliation_required') return 'Reconciliation required';
    if (attempt == 'failed' || payment == 'failed') return 'Verified failure';
    if (attempt == 'expired') return 'Payment session expired';
    if (attempt == 'pending' ||
        attempt == 'session_created' ||
        payment == 'pending') {
      return 'Payment pending';
    }
    if (payment == 'not_collected') return 'Not collected';
    return payment;
  }

  static String _refundLabel(String status) => switch (status) {
    'requested' => 'Awaiting finance review',
    'approved' => 'Approved',
    'processing' => 'Processing',
    'succeeded' => 'Verified sandbox refund',
    'failed' => 'Failed',
    'rejected' => 'Rejected',
    'reconciliation_required' => 'Needs reconciliation',
    _ => status,
  };
}

class _CODStatusCard extends ConsumerStatefulWidget {
  const _CODStatusCard({required this.orderId, required this.paymentStatus});
  final String orderId;
  final String paymentStatus;

  @override
  ConsumerState<_CODStatusCard> createState() => _CODStatusCardState();
}

class _CODStatusCardState extends ConsumerState<_CODStatusCard> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(codStatusRepositoryProvider)
          .getCustomerStatus(widget.orderId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Cash-on-delivery status is unavailable. Refresh to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cod = _data?['cod'] is Map
        ? Map<String, dynamic>.from(_data!['cod'] as Map)
        : null;
    final minor = (cod?['amount_minor'] as num?)?.toInt();
    final collected = cod?['collected'] == true;
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, color: AppTheme.emerald),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Cash on Delivery',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: 'Refresh COD status',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'SYNTHETIC QA ONLY · No physical cash is handled.',
                style: TextStyle(
                  color: Color(0xFF8A4B00),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading && _data == null) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Retry'),
                ),
              ),
            ],
            if (cod != null) ...[
              OrderPaymentCard._line(
                'COD amount',
                minor == null ? 'Unavailable' : OrderPaymentCard._money(minor),
              ),
              OrderPaymentCard._line(
                'Collection',
                collected ? 'Confirmed at verified handover' : 'Not collected',
              ),
              OrderPaymentCard._line(
                'Electronic payment status',
                widget.paymentStatus,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'The assigned rider records the synthetic collection only after the customer delivery code is verified. This does not mark an electronic payment as paid.',
                  style: TextStyle(color: Color(0xFF667085)),
                ),
              ),
            ] else if (!_loading && _error == null)
              const Text(
                'COD details are not available for this order.',
                style: TextStyle(color: Color(0xFF667085)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReasonOption extends StatelessWidget {
  const _ReasonOption(this.code, this.label);
  final String code, label;
  @override
  Widget build(BuildContext context) => SimpleDialogOption(
    onPressed: () => Navigator.pop(context, code),
    child: Text(label),
  );
}
