import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:grepmind_mobile/core/models/merchant_finance.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/merchant_finance_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class MerchantEarningsScreen extends ConsumerStatefulWidget {
  const MerchantEarningsScreen({super.key, this.businessId});

  /// Optional business override is useful for route-level tests. Normal merchant
  /// sessions resolve the active business from the authenticated profile.
  final String? businessId;

  @override
  ConsumerState<MerchantEarningsScreen> createState() =>
      _MerchantEarningsScreenState();
}

class _MerchantEarningsScreenState
    extends ConsumerState<MerchantEarningsScreen> {
  String? _businessId;
  String? _businessError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    var profile = ref.read(merchantProfileProvider('')).profile;
    var id = widget.businessId ?? profile?['id']?.toString();
    if (id == null || id.isEmpty) {
      await ref.read(merchantProfileProvider('').notifier).load();
      profile = ref.read(merchantProfileProvider('')).profile;
      id = widget.businessId ?? profile?['id']?.toString();
    }
    if (!mounted) return;
    if (id == null || id.isEmpty) {
      setState(
        () => _businessError = 'Choose an approved merchant business to view its financial records.',
      );
      return;
    }
    setState(() {
      _businessId = id;
      _businessError = null;
    });
  }

  Future<void> _refresh() async {
    final id = _businessId;
    if (id == null) {
      await _initialize();
    } else {
      ref.invalidate(merchantFinanceProvider(id));
      try {
        await ref.read(merchantFinanceProvider(id).future);
      } catch (_) {
        // The provider exposes the refreshed error state to the screen.
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text('Earnings & Payouts'),
      backgroundColor: Colors.white,
      actions: [
        IconButton(
          tooltip: 'Refresh financial records',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _businessError != null
        ? _BusinessErrorState(message: _businessError!, onRetry: _initialize)
        : _businessId == null
        ? const Center(child: CircularProgressIndicator())
        : _MerchantFinanceBody(businessId: _businessId!, onRefresh: _refresh),
  );
}

class _MerchantFinanceBody extends ConsumerStatefulWidget {
  const _MerchantFinanceBody({
    required this.businessId,
    required this.onRefresh,
  });

  final String businessId;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_MerchantFinanceBody> createState() =>
      _MerchantFinanceBodyState();
}

class _MerchantFinanceBodyState extends ConsumerState<_MerchantFinanceBody> {
  int? _historyDays;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(merchantFinanceProvider(widget.businessId));
    final data = state.asData?.value;
    final errorMessage = state.hasError
        ? 'Could not load merchant financial records. Check your connection and retry.'
        : null;
    final payables = _filterPayables(data?.payables ?? const []);
    final settlements = _filterSettlements(data?.settlements ?? const []);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const _SimulationDisclosure(),
          if (errorMessage != null)
            _ErrorCard(message: errorMessage, onRetry: widget.onRefresh),
          if (state.isLoading && data == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (data == null && !state.hasError)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('Financial records are not available.'),
              ),
            )
          else if (data != null) ...[
            _overview(data.overview),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Financial history',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ),
                if (state.isLoading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _dateFilters(),
            const SizedBox(height: 18),
            const Text(
              'Order payables',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (payables.isEmpty)
              const _EmptyCard(
                icon: Icons.receipt_long_outlined,
                title: 'No payable records for this period',
                subtitle: 'Eligible order payables will appear here when recorded by Grepmind.',
              )
            else
              for (final row in payables)
                _PayableTile(
                  record: row,
                  onTap: () => _showPayableDetails(context, row),
                ),
            const SizedBox(height: 20),
            const Text(
              'Settlement history',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (settlements.isEmpty)
              const _EmptyCard(
                icon: Icons.account_balance_outlined,
                title: 'No settlement records for this period',
                subtitle: 'Settlement status will be shown here when the backend records it.',
              )
            else
              for (final row in settlements)
                _SettlementTile(
                  record: row,
                  onTap: () => _showSettlementDetails(context, row),
                ),
            const SizedBox(height: 8),
            Text(
              'Summary amounts are all-time server totals. The date filter applies to the history lists.',
              style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _overview(MerchantFinanceOverview overview) {
    final cards = [
      _Metric(
        label: 'Pending payable',
        amount: overview.pendingPayableMinor,
        currency: overview.currency,
        icon: Icons.hourglass_bottom_rounded,
      ),
      _Metric(
        label: 'Net payable snapshots',
        amount: overview.netPayableMinor,
        currency: overview.currency,
        icon: Icons.receipt_long_rounded,
      ),
      _Metric(
        label: 'Simulated / reconciled',
        amount: overview.simulatedSettlementMinor,
        currency: overview.currency,
        icon: Icons.fact_check_outlined,
      ),
      _Metric(
        label: 'Approved adjustments',
        amount: overview.approvedAdjustmentsMinor,
        currency: overview.currency,
        icon: Icons.tune_rounded,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Merchant financial overview',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Amounts are read from this business’s authorized financial records.',
          style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: cards
                  .map((metric) => SizedBox(width: width, child: metric))
                  .toList(growable: false),
            );
          },
        ),
        if (!overview.realPayoutsEnabled)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'No amount is available for withdrawal. Real payouts are disabled.',
              style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
            ),
          ),
      ],
    );
  }

  Widget _dateFilters() => Wrap(
    spacing: 8,
    children: [
      _filterChip('All', null),
      _filterChip('7 days', 7),
      _filterChip('30 days', 30),
      _filterChip('90 days', 90),
    ],
  );

  Widget _filterChip(String label, int? days) => ChoiceChip(
    label: Text(label),
    selected: _historyDays == days,
    onSelected: (_) => setState(() => _historyDays = days),
  );

  List<MerchantPayableRecord> _filterPayables(
    List<MerchantPayableRecord> values,
  ) => values.where((row) => _inRange(row.createdAt)).toList(growable: false);

  List<MerchantSettlementRecord> _filterSettlements(
    List<MerchantSettlementRecord> values,
  ) => values.where((row) => _inRange(row.createdAt)).toList(growable: false);

  bool _inRange(DateTime? date) {
    final days = _historyDays;
    if (days == null) return true;
    if (date == null) return false;
    return !date.isBefore(DateTime.now().subtract(Duration(days: days)));
  }

  void _showPayableDetails(BuildContext context, MerchantPayableRecord row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DetailsSheet(
        title: row.referenceCode,
        subtitle: 'Order payable · ${_paymentLabel(row.paymentSource)}',
        rows: [
          _DetailRow(
            'Customer order gross',
            _money(row.customerGrossMinor, row.currency),
          ),
          _DetailRow(
            'Partner supply basis',
            _money(row.partnerGrossMinor, row.currency),
          ),
          _DetailRow('Commission', _money(row.commissionMinor, row.currency)),
          _DetailRow(
            'Approved adjustments',
            _money(row.adjustmentMinor, row.currency),
          ),
          _DetailRow(
            'Net payable snapshot',
            _money(row.netPayableMinor, row.currency),
            emphasized: true,
          ),
          _DetailRow('Payable state', _stateLabel(row.state)),
          _DetailRow('Policy version', row.policyVersion.toString()),
          if (row.createdAt != null)
            _DetailRow('Recorded', _date(row.createdAt!)),
        ],
        disclosure: 'This payable snapshot is not proof of available funds or a bank payout.',
      ),
    );
  }

  void _showSettlementDetails(
    BuildContext context,
    MerchantSettlementRecord row,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DetailsSheet(
        title: 'Settlement ${_stateLabel(row.status)}',
        subtitle: 'Period ${row.periodStart} – ${row.periodEnd}',
        rows: [
          _DetailRow('Payable amount', _money(row.payableMinor, row.currency)),
          _DetailRow('Adjustments', _money(row.adjustmentMinor, row.currency)),
          _DetailRow(
            'Simulated amount',
            _money(row.simulatedNetMinor, row.currency),
            emphasized: true,
          ),
          _DetailRow('State', _stateLabel(row.status)),
          _DetailRow('Funding source', _stateLabel(row.fundingMode)),
          if (row.simulatedAt != null)
            _DetailRow('Simulation recorded', _date(row.simulatedAt!)),
        ],
        disclosure: row.disclosure,
      ),
    );
  }
}

class _SimulationDisclosure extends StatelessWidget {
  const _SimulationDisclosure();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF1FF),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFC7D8FA)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: AppTheme.primary),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Read-only financial information. Simulated settlements are not bank payouts; no payout controls are available in this app.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.amount,
    required this.currency,
    required this.icon,
  });

  final String label;
  final int amount;
  final String currency;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 116),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2EAF5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
        ),
        const SizedBox(height: 4),
        Text(
          _money(amount, currency),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _PayableTile extends StatelessWidget {
  const _PayableTile({required this.record, required this.onTap});
  final MerchantPayableRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: const BorderSide(color: Color(0xFFE4EAF4)),
    ),
    child: ListTile(
      minVerticalPadding: 12,
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFEAF1FF),
        child: Icon(Icons.receipt_long_outlined, color: AppTheme.primary),
      ),
      title: Text(
        record.referenceCode,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${_paymentLabel(record.paymentSource)} · ${_stateLabel(record.state)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _money(record.netPayableMinor, record.currency),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: onTap,
    ),
  );
}

class _SettlementTile extends StatelessWidget {
  const _SettlementTile({required this.record, required this.onTap});
  final MerchantSettlementRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: const BorderSide(color: Color(0xFFE4EAF4)),
    ),
    child: ListTile(
      minVerticalPadding: 12,
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFE9F7F2),
        child: Icon(Icons.account_balance_outlined, color: Color(0xFF0F766E)),
      ),
      title: Text(
        '${_money(record.simulatedNetMinor, record.currency)} · ${_stateLabel(record.status)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${record.periodStart} – ${record.periodEnd} · simulation only',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.disclosure,
  });

  final String title;
  final String subtitle;
  final List<_DetailRow> rows;
  final String disclosure;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppTheme.secondaryText)),
          const SizedBox(height: 14),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: TextStyle(
                        fontWeight: row.emphasized
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    row.value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontWeight: row.emphasized
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 22),
          Text(
            disclosure,
            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
        ],
      ),
    ),
  );
}

class _DetailRow {
  const _DetailRow(this.label, this.value, {this.emphasized = false});
  final String label;
  final String value;
  final bool emphasized;
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      children: [
        Icon(icon, color: AppTheme.secondaryText, size: 28),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F0),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _BusinessErrorState extends StatelessWidget {
  const _BusinessErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.store_mall_directory_outlined, size: 38),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

String _money(int minor, String currency) {
  final amount = minor.abs();
  final whole = NumberFormat.decimalPattern('en_IN').format(amount ~/ 100);
  final fraction = (amount % 100).toString().padLeft(2, '0');
  final symbol = currency.toUpperCase() == 'INR' ? '₹' : '$currency ';
  return '${minor < 0 ? '−' : ''}$symbol$whole.$fraction';
}

String _paymentLabel(String source) {
  final normalized = source.toLowerCase();
  if (normalized.contains('cod') || normalized.contains('cash')) return 'COD';
  if (normalized.contains('upi')) return 'UPI';
  return _stateLabel(source);
}

String _stateLabel(String state) => state
    .replaceAll('_', ' ')
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _date(DateTime date) => DateFormat.yMMMd().format(date.toLocal());
