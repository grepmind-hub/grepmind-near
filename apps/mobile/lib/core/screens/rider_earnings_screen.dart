import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

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
    if (mounted) setState(() { _loading = true; _error = null; });
    final end = DateTime.now().toUtc();
    final start = end.subtract(Duration(days: _days));
    final range = {'from': start.toIso8601String(), 'to': end.toIso8601String()};
    try {
      final results = await Future.wait([
        apiClient.get('/rider/earnings/summary', queryParameters: range),
        apiClient.get('/rider/earnings', queryParameters: {...range, 'limit': 50}),
      ]);
      final summaryData = (results[0].data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      final rawEntries = (results[1].data as Map<String, dynamic>)['data'] as List<dynamic>? ?? const [];
      if (!mounted) return;
      setState(() {
        _summary = summaryData;
        _entries = rawEntries.whereType<Map<String, dynamic>>().toList(growable: false);
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Earnings could not be loaded. Check your connection and retry.');
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
    final currencyTotals = (summary?['currency_totals'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList(growable: false);
    final hasMultipleCurrencies = currencyTotals.length > 1;
    final completed = hasMultipleCurrencies
        ? currencyTotals.fold<int>(0, (sum, row) => sum + ((row['completed_deliveries'] as num?)?.toInt() ?? 0))
        : (summary?['completed_deliveries'] as num?)?.toInt();
    final unpriced = hasMultipleCurrencies
        ? currencyTotals.fold<int>(0, (sum, row) => sum + ((row['unpriced_deliveries'] as num?)?.toInt() ?? 0))
        : (summary?['unpriced_deliveries'] as num?)?.toInt();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Rider earnings'), backgroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD8E3F5))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Recorded compensation', style: TextStyle(color: AppTheme.secondaryText, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_loading && summary == null)
                  const Text('Loading…', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF172033)))
                else if (hasMultipleCurrencies) ...[
                  for (final total in currencyTotals)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text(_money(total['total_recorded_minor'], total['currency']?.toString() ?? 'INR'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF172033)))),
                ] else
                  Text(_money(summary?['total_recorded_minor'], currency), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF172033))),
                const SizedBox(height: 8),
                Text('${completed ?? '—'} completed deliveries · last $_days days', style: const TextStyle(color: AppTheme.secondaryText)),
                const SizedBox(height: 16),
                const Text('Payouts are not available. This screen shows ledger records only; no transfers or paid status are implied.', style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.secondaryText)),
              ]),
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 7, label: Text('7 days')), ButtonSegment(value: 30, label: Text('30 days')), ButtonSegment(value: 90, label: Text('90 days'))],
              selected: {_days},
              onSelectionChanged: (selection) { setState(() => _days = selection.first); _load(); },
            ),
            if (summary != null && (unpriced ?? 0) > 0) ...[
              const SizedBox(height: 14),
              Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF2D28B))), child: Text('$unpriced completed deliveries are awaiting an approved compensation policy.', style: const TextStyle(color: Color(0xFF72520A)))),
            ],
            const SizedBox(height: 20),
            const Text('Ledger activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [Text(_error!, textAlign: TextAlign.center), TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry'))])),
            ] else if (_loading && _entries.isEmpty) ...[
              const SizedBox(height: 12), const LinearProgressIndicator(),
            ] else if (_entries.isEmpty) ...[
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: const Column(children: [Icon(Icons.receipt_long_outlined, size: 34, color: AppTheme.secondaryText), SizedBox(height: 8), Text('No ledger activity for this period', style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(height: 4), Text('Eligible completed deliveries will appear here when compensation policy is approved.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText))])),
            ] else ...[
              const SizedBox(height: 8),
              for (final row in _entries) _entryCard(row, currency),
            ],
          ],
        ),
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> row, String currency) {
    final type = row['entry_type']?.toString() ?? 'entry';
    final date = DateTime.tryParse(row['effective_at']?.toString() ?? '')?.toLocal();
    final label = switch (type) {'delivery_earning' => 'Completed delivery', 'manual_adjustment' => 'Admin adjustment', 'bonus' => 'Approved bonus', 'reversal' => 'Reversal', 'correction' => 'Correction', _ => 'Awaiting policy review'};
    return Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE4EAF4))), child: Row(children: [const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF2457D6)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.w700)), if (date != null) Text('${date.day}/${date.month}/${date.year}', style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText)), if (row['reason'] != null) Text(row['reason'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText))])), Text(_money(row['amount_minor'], row['currency']?.toString() ?? currency), style: const TextStyle(fontWeight: FontWeight.w800))]));
  }
}
