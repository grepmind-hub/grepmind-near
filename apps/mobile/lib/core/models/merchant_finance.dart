class MerchantFinanceOverview {
  final String currency;
  final int customerGrossMinor;
  final int partnerGrossMinor;
  final int commissionMinor;
  final int netPayableMinor;
  final int pendingPayableMinor;
  final int approvedAdjustmentsMinor;
  final int simulatedSettlementMinor;
  final String settlementMode;
  final bool realPayoutsEnabled;

  const MerchantFinanceOverview({
    required this.currency,
    required this.customerGrossMinor,
    required this.partnerGrossMinor,
    required this.commissionMinor,
    required this.netPayableMinor,
    required this.pendingPayableMinor,
    required this.approvedAdjustmentsMinor,
    required this.simulatedSettlementMinor,
    required this.settlementMode,
    required this.realPayoutsEnabled,
  });

  factory MerchantFinanceOverview.fromJson(Map<String, dynamic> json) =>
      MerchantFinanceOverview(
        currency: json['currency']?.toString() ?? 'INR',
        customerGrossMinor: _minor(json['customer_gross_minor']),
        partnerGrossMinor: _minor(json['partner_gross_minor']),
        commissionMinor: _minor(json['commission_minor']),
        netPayableMinor: _minor(json['net_payable_minor']),
        pendingPayableMinor: _minor(json['pending_payable_minor']),
        approvedAdjustmentsMinor: _minor(json['approved_adjustments_minor']),
        simulatedSettlementMinor: _minor(json['simulated_settlement_minor']),
        settlementMode: json['settlement_mode']?.toString() ?? 'unknown',
        realPayoutsEnabled: json['real_payouts_enabled'] == true,
      );
}

class MerchantPayableRecord {
  final String id;
  final String orderId;
  final String referenceCode;
  final String currency;
  final int customerGrossMinor;
  final int partnerGrossMinor;
  final int commissionMinor;
  final int netPayableMinor;
  final int adjustmentMinor;
  final int policyVersion;
  final String paymentSource;
  final String state;
  final DateTime? createdAt;

  const MerchantPayableRecord({
    required this.id,
    required this.orderId,
    required this.referenceCode,
    required this.currency,
    required this.customerGrossMinor,
    required this.partnerGrossMinor,
    required this.commissionMinor,
    required this.netPayableMinor,
    required this.adjustmentMinor,
    required this.policyVersion,
    required this.paymentSource,
    required this.state,
    required this.createdAt,
  });

  factory MerchantPayableRecord.fromJson(Map<String, dynamic> json) =>
      MerchantPayableRecord(
        id: json['id']?.toString() ?? '',
        orderId: json['order_id']?.toString() ?? '',
        referenceCode: json['reference_code']?.toString() ?? 'Order',
        currency: json['currency']?.toString() ?? 'INR',
        customerGrossMinor: _minor(json['customer_gross_minor']),
        partnerGrossMinor: _minor(json['partner_gross_minor']),
        commissionMinor: _minor(json['commission_minor']),
        netPayableMinor: _minor(json['net_payable_minor']),
        adjustmentMinor: _minor(json['adjustment_minor']),
        policyVersion: _minor(json['policy_version']),
        paymentSource: json['payment_source']?.toString() ?? 'unknown',
        state: json['state']?.toString() ?? 'pending',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );
}

class MerchantSettlementRecord {
  final String id;
  final String currency;
  final String periodStart;
  final String periodEnd;
  final int payableMinor;
  final int adjustmentMinor;
  final int simulatedNetMinor;
  final String status;
  final String fundingMode;
  final String disclosure;
  final DateTime? createdAt;
  final DateTime? simulatedAt;

  const MerchantSettlementRecord({
    required this.id,
    required this.currency,
    required this.periodStart,
    required this.periodEnd,
    required this.payableMinor,
    required this.adjustmentMinor,
    required this.simulatedNetMinor,
    required this.status,
    required this.fundingMode,
    required this.disclosure,
    required this.createdAt,
    required this.simulatedAt,
  });

  factory MerchantSettlementRecord.fromJson(Map<String, dynamic> json) =>
      MerchantSettlementRecord(
        id: json['id']?.toString() ?? '',
        currency: json['currency']?.toString() ?? 'INR',
        periodStart: json['period_start']?.toString() ?? '',
        periodEnd: json['period_end']?.toString() ?? '',
        payableMinor: _minor(json['payable_minor']),
        adjustmentMinor: _minor(json['adjustment_minor']),
        simulatedNetMinor: _minor(json['simulated_net_minor']),
        status: json['status']?.toString() ?? 'unknown',
        fundingMode: json['funding_mode']?.toString() ?? 'unknown',
        disclosure:
            json['disclosure']?.toString() ??
            'Simulation only. No external payout is implied.',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
        simulatedAt: DateTime.tryParse(json['simulated_at']?.toString() ?? ''),
      );
}

int _minor(dynamic value) => switch (value) {
  final int n => n,
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};
