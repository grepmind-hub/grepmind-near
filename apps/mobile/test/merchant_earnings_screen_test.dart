import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/merchant_finance.dart';
import 'package:grepmind_mobile/core/providers/merchant_finance_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_earnings_screen.dart';

class _FakeMerchantFinanceRepository implements MerchantFinanceRepository {
  _FakeMerchantFinanceRepository(this.data, {this.failFirst = false});

  final MerchantFinanceData data;
  final bool failFirst;
  int calls = 0;

  @override
  Future<MerchantFinanceData> load(String businessId) async {
    expect(businessId, 'merchant-business-1');
    calls++;
    if (failFirst && calls == 1) throw StateError('offline');
    return data;
  }
}

MerchantFinanceData _qaFinanceData({
  bool includeOldOrder = true,
  bool includeCurrentOrder = true,
}) {
  final now = DateTime.now();
  return MerchantFinanceData(
    overview: const MerchantFinanceOverview(
      currency: 'INR',
      customerGrossMinor: 69000,
      partnerGrossMinor: 44000,
      commissionMinor: 0,
      netPayableMinor: 44000,
      pendingPayableMinor: 0,
      approvedAdjustmentsMinor: 0,
      simulatedSettlementMinor: 44000,
      settlementMode: 'simulated_only',
      realPayoutsEnabled: false,
    ),
    payables: [
      if (includeCurrentOrder)
        MerchantPayableRecord(
          id: 'payable-upi',
          orderId: 'order-upi',
          referenceCode: 'GN-0A130595',
          currency: 'INR',
          customerGrossMinor: 34500,
          partnerGrossMinor: 22000,
          commissionMinor: 0,
          netPayableMinor: 22000,
          adjustmentMinor: 0,
          policyVersion: 1,
          paymentSource: 'sandbox_upi_capture',
          state: 'allocated',
          createdAt: now,
        ),
      if (includeOldOrder)
        MerchantPayableRecord(
          id: 'payable-cod',
          orderId: 'order-cod',
          referenceCode: 'GN-E2F76199',
          currency: 'INR',
          customerGrossMinor: 34500,
          partnerGrossMinor: 22000,
          commissionMinor: 0,
          netPayableMinor: 22000,
          adjustmentMinor: 0,
          policyVersion: 1,
          paymentSource: 'synthetic_cod_collection',
          state: 'allocated',
          createdAt: now.subtract(const Duration(days: 120)),
        ),
    ],
    settlements: [
      if (includeCurrentOrder)
        MerchantSettlementRecord(
          id: 'settlement-upi',
          currency: 'INR',
          periodStart: '2026-11-01',
          periodEnd: '2026-11-13',
          payableMinor: 22000,
          adjustmentMinor: 0,
          simulatedNetMinor: 22000,
          status: 'reconciled',
          fundingMode: 'synthetic_qa_pool',
          disclosure: 'SIMULATED ONLY — NOT A REAL PAYOUT',
          createdAt: now,
          simulatedAt: now,
        ),
      if (includeOldOrder)
        MerchantSettlementRecord(
          id: 'settlement-cod',
          currency: 'INR',
          periodStart: '2026-07-01',
          periodEnd: '2026-07-01',
          payableMinor: 22000,
          adjustmentMinor: 0,
          simulatedNetMinor: 22000,
          status: 'reconciled',
          fundingMode: 'verified_cod_remittance',
          disclosure: 'SIMULATED ONLY — NOT A REAL PAYOUT',
          createdAt: now.subtract(const Duration(days: 120)),
          simulatedAt: now.subtract(const Duration(days: 120)),
        ),
    ],
  );
}

void main() {
  testWidgets('shows backend payable and simulated settlement snapshots', (
    tester,
  ) async {
    final repository = _FakeMerchantFinanceRepository(_qaFinanceData());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantFinanceRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: MerchantEarningsScreen(businessId: 'merchant-business-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending payable'), findsOneWidget);
    expect(find.text('Net payable snapshots'), findsOneWidget);
    expect(find.text('Simulated / reconciled'), findsOneWidget);
    expect(find.text('₹440.00'), findsWidgets);
    await _scrollTo(tester, find.text('GN-0A130595'));
    expect(find.text('GN-0A130595'), findsOneWidget);
    expect(find.text('GN-E2F76199'), findsOneWidget);
    expect(find.text('UPI · Allocated'), findsOneWidget);
    await _scrollTo(
      tester,
      find.text('2026-11-01 – 2026-11-13 · simulation only'),
    );
    expect(find.textContaining('simulation only'), findsWidgets);
    await _scrollTo(
      tester,
      find.text(
        'No amount is available for withdrawal. Real payouts are disabled.',
      ),
    );
    expect(
      find.text(
        'No amount is available for withdrawal. Real payouts are disabled.',
      ),
      findsOneWidget,
    );
    expect(find.text('Paid to bank'), findsNothing);
    expect(repository.calls, 1);

    await tester.tap(find.text('GN-0A130595'));
    await tester.pumpAndSettle();
    expect(find.text('Partner supply basis'), findsOneWidget);
    expect(find.text('Net payable snapshot'), findsOneWidget);
    expect(find.textContaining('not proof of available funds'), findsOneWidget);
  });

  testWidgets(
    'date filter applies to history while overview remains all-time',
    (tester) async {
      final repository = _FakeMerchantFinanceRepository(_qaFinanceData());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            merchantFinanceRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: MerchantEarningsScreen(businessId: 'merchant-business-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('7 days'));
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(find.text('GN-0A130595'), findsOneWidget);
      expect(find.text('GN-E2F76199'), findsNothing);
      expect(
        find.textContaining('Summary amounts are all-time'),
        findsOneWidget,
      );
      expect(find.text('₹440.00'), findsWidgets);
    },
  );

  testWidgets('shows the empty state when there are no records', (
    tester,
  ) async {
    final repository = _FakeMerchantFinanceRepository(
      _qaFinanceData(includeCurrentOrder: false, includeOldOrder: false),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantFinanceRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: MerchantEarningsScreen(businessId: 'merchant-business-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('No payable records for this period'));
    expect(find.text('No payable records for this period'), findsOneWidget);
    await _scrollTo(tester, find.text('No settlement records for this period'));
    expect(find.text('No settlement records for this period'), findsOneWidget);
  });

  testWidgets('shows an error and retries successfully', (tester) async {
    final repository = _FakeMerchantFinanceRepository(
      _qaFinanceData(includeOldOrder: false),
      failFirst: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantFinanceRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: MerchantEarningsScreen(businessId: 'merchant-business-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not load merchant financial records'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('GN-0A130595'));
    expect(find.text('GN-0A130595'), findsOneWidget);
    expect(repository.calls, 2);
  });
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 16 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
  }
}
