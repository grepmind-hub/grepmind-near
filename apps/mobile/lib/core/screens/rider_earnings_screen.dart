import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/rider_workspace_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/luxe_components.dart';

class RiderEarningsScreen extends StatefulWidget {
  const RiderEarningsScreen({super.key});

  @override
  State<RiderEarningsScreen> createState() => _RiderEarningsScreenState();
}

class _RiderEarningsScreenState extends State<RiderEarningsScreen> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _entries = const [];
  bool _loading = true;
  String? _error;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final end = DateTime.now().toUtc();
    final start = end.subtract(Duration(days: _days));
    final range = {
      'from': start.toIso8601String(),
      'to': end.toIso8601String(),
    };
    try {
      final results = await Future.wait([
        apiClient.get('/rider/earnings/summary', queryParameters: range),
        apiClient.get(
          '/rider/earnings',
          queryParameters: {...range, 'limit': 50},
        ),
      ]);
      final summaryData =
          (results[0].data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final rawEntries =
          (results[1].data as Map<String, dynamic>)['data']
              as List<dynamic>? ??
          const [];
      if (!mounted) return;
      setState(() {
        _summary = summaryData;
        _entries = rawEntries.whereType<Map<String, dynamic>>().toList(
          growable: false,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'Earnings could not be loaded. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(dynamic minor, String currency) {
    final value = switch (minor) {
      final String text => int.tryParse(text),
      final num number => number.toInt(),
      _ => null,
    };
    if (value == null) return 'Awaiting policy review';
    final whole = value.abs() ~/ 100;
    final fraction = (value.abs() % 100).toString().padLeft(2, '0');
    return '${value < 0 ? '−' : ''}$currency $whole.$fraction';
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final currency = summary?['currency']?.toString() ?? 'INR';
    final currencyTotals =
        (summary?['currency_totals'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
    final hasMultipleCurrencies = currencyTotals.length > 1;
    final completed =
        hasMultipleCurrencies
            ? currencyTotals.fold<int>(
              0,
              (sum, row) =>
                  sum + ((row['completed_deliveries'] as num?)?.toInt() ?? 0),
            )
            : (summary?['completed_deliveries'] as num?)?.toInt();
    final unpriced =
        hasMultipleCurrencies
            ? currencyTotals.fold<int>(
              0,
              (sum, row) =>
                  sum + ((row['unpriced_deliveries'] as num?)?.toInt() ?? 0),
            )
            : (summary?['unpriced_deliveries'] as num?)?.toInt();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          'Rider earnings',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.riderAmberBorder),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.riderAmber.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recorded compensation',
                    style: TextStyle(
                      color: AppTheme.secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_loading && summary == null)
                    const Text(
                      'Loading…',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF172033),
                      ),
                    )
                  else if (hasMultipleCurrencies) ...[
                    for (final total in currencyTotals)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _money(
                            total['total_recorded_minor'],
                            total['currency']?.toString() ?? 'INR',
                          ),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF172033),
                          ),
                        ),
                      ),
                  ] else
                    Text(
                      _money(summary?['total_recorded_minor'], currency),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF172033),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '${completed ?? '—'} completed deliveries · last $_days days',
                    style: const TextStyle(color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Payouts are not available. This screen shows ledger records only; no transfers or paid status are implied.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
                ButtonSegment(value: 90, label: Text('90 days')),
              ],
              selected: {_days},
              onSelectionChanged: (selection) {
                setState(() => _days = selection.first);
                _load();
              },
            ),
            if (summary != null && (unpriced ?? 0) > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.amberLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '$unpriced completed deliveries are awaiting an approved compensation policy.',
                  style: const TextStyle(color: Color(0xFF78350F)),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Ledger activity',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ] else if (_loading && _entries.isEmpty) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else if (_entries.isEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 34,
                      color: AppTheme.secondaryText,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No ledger activity for this period',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Eligible completed deliveries will appear here when compensation policy is approved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              for (final row in _entries) _entryCard(row, currency),
            ],
            const SizedBox(height: 20),
            const _CashAccountabilityTile(),
            const SizedBox(height: 16),
            const _RiderBeneficiarySection(),
          ],
        ),
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> row, String currency) {
    final type = row['entry_type']?.toString() ?? 'entry';
    final date =
        DateTime.tryParse(row['effective_at']?.toString() ?? '')?.toLocal();
    final label = switch (type) {
      'delivery_earning' => 'Completed delivery',
      'manual_adjustment' => 'Admin adjustment',
      'bonus' => 'Approved bonus',
      'reversal' => 'Reversal',
      'correction' => 'Correction',
      _ => 'Awaiting policy review',
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE4EAF4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.riderAmberContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppTheme.riderAmberDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (date != null)
                  Text(
                    '${date.day}/${date.month}/${date.year}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                if (row['reason'] != null)
                  Text(
                    row['reason'].toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryText,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _money(row['amount_minor'], row['currency']?.toString() ?? currency),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CashAccountabilityTile extends StatelessWidget {
  const _CashAccountabilityTile();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.riderAmberContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.account_balance_wallet_outlined,
            color: AppTheme.riderAmberDark,
            size: 22,
          ),
        ),
        title: const Text(
          'Cash Accountability',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: const Text(
          'COD collections & remittance history (separate from earnings)',
          style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppTheme.secondaryText,
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RiderCashAccountabilityScreen(),
          ),
        ),
      ),
    );
  }
}

class _RiderBeneficiarySection extends StatefulWidget {
  const _RiderBeneficiarySection();

  @override
  State<_RiderBeneficiarySection> createState() =>
      _RiderBeneficiarySectionState();
}

class _RiderBeneficiarySectionState extends State<_RiderBeneficiarySection> {
  Map<String, dynamic>? _beneficiary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await apiClient.get('/rider/bank-beneficiary');
      final raw = res.data;
      final data =
          raw is Map<String, dynamic>
              ? (raw['data'] is Map<String, dynamic>
                  ? raw['data'] as Map<String, dynamic>
                  : (raw['account_holder_name'] != null ? raw : null))
              : null;
      if (mounted) {
        setState(() {
          _beneficiary = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _beneficiary = null;
          _loading = false;
        });
      }
    }
  }

  void _openAddBankSheet() {
    final nameCtrl = TextEditingController();
    final acctCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool submitting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (context, setModalState) => Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Register Rider Bank Account',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.riderAmberDeep,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enter verified bank account details for rider payouts.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Account Holder Name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator:
                              (v) =>
                                  (v == null || v.trim().length < 3)
                                      ? 'Enter full name (min 3 chars)'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: acctCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Bank Account Number',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator:
                              (v) =>
                                  (v == null || v.trim().length < 8)
                                      ? 'Enter account number (min 8 digits)'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: bankCtrl,
                          decoration: InputDecoration(
                            labelText: 'Bank Name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator:
                              (v) =>
                                  (v == null || v.trim().length < 2)
                                      ? 'Enter bank name'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: ifscCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'IFSC Code',
                            hintText: 'e.g. SBIN0001234',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length != 11) {
                              return 'Enter 11-character IFSC code';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.riderAmberDark,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed:
                                submitting
                                    ? null
                                    : () async {
                                      if (!formKey.currentState!.validate()) {
                                        return;
                                      }
                                      setModalState(() => submitting = true);
                                      final messenger = ScaffoldMessenger.of(context);
                                      final ctxMessenger = ScaffoldMessenger.of(ctx);
                                      try {
                                        await apiClient.post(
                                          '/rider/bank-beneficiary',
                                          data: {
                                            'account_holder_name':
                                                nameCtrl.text.trim(),
                                            'account_number':
                                                acctCtrl.text.trim(),
                                            'bank_name': bankCtrl.text.trim(),
                                            'ifsc_code':
                                                ifscCtrl.text
                                                    .trim()
                                                    .toUpperCase(),
                                          },
                                        );
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Bank details submitted for verification.',
                                              ),
                                            ),
                                          );
                                          _fetch();
                                        }
                                      } catch (_) {
                                        setModalState(() => submitting = false);
                                        if (ctx.mounted) {
                                          ctxMessenger.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Failed to submit bank details. Try again.',
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                            child:
                                submitting
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text(
                                      'Save Bank Account',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }
    final b = _beneficiary;
    if (b != null) {
      return LuxeBeneficiaryCard(
        accountHolderName: b['account_holder_name']?.toString() ?? 'Rider',
        accountNumberMasked:
            b['account_number_masked']?.toString() ?? '••••••••',
        ifscCode: b['ifsc_code']?.toString() ?? '',
        bankName: b['bank_name']?.toString(),
        verificationStatus: b['verification_status']?.toString() ?? 'pending',
        onEdit: _openAddBankSheet,
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.riderAmberContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_balance_outlined,
              color: AppTheme.riderAmberDark,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settlement Bank Account',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Register your bank details for verified payouts.',
                  style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _openAddBankSheet,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.riderAmberDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text(
              'Add Bank',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
