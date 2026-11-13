import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/merchant_finance.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

class MerchantFinanceData {
  final MerchantFinanceOverview overview;
  final List<MerchantPayableRecord> payables;
  final List<MerchantSettlementRecord> settlements;

  const MerchantFinanceData({
    required this.overview,
    required this.payables,
    required this.settlements,
  });
}

abstract class MerchantFinanceRepository {
  Future<MerchantFinanceData> load(String businessId);
}

class ApiMerchantFinanceRepository implements MerchantFinanceRepository {
  @override
  Future<MerchantFinanceData> load(String businessId) async {
    final encodedBusinessId = Uri.encodeComponent(businessId);
    final responses = await Future.wait([
      apiClient.get('/merchant/businesses/$encodedBusinessId/finance/overview'),
      apiClient.get('/merchant/businesses/$encodedBusinessId/finance/payables'),
      apiClient.get(
        '/merchant/businesses/$encodedBusinessId/finance/settlements',
      ),
    ]);
    final overview = _payloadMap(responses[0].data);
    final payables = _payloadList(responses[1].data)
        .map(MerchantPayableRecord.fromJson)
        .toList(growable: false);
    final settlements = _payloadList(responses[2].data)
        .map(MerchantSettlementRecord.fromJson)
        .toList(growable: false);
    return MerchantFinanceData(
      overview: MerchantFinanceOverview.fromJson(overview),
      payables: payables,
      settlements: settlements,
    );
  }

  Map<String, dynamic> _payloadMap(dynamic response) {
    if (response is Map<String, dynamic>) {
      final data = response['data'];
      if (data is Map<String, dynamic>) return data;
      return response;
    }
    throw const FormatException('Invalid merchant finance response.');
  }

  List<Map<String, dynamic>> _payloadList(dynamic response) {
    final data = response is Map<String, dynamic> ? response['data'] : response;
    if (data is! List) {
      throw const FormatException('Invalid merchant finance history.');
    }
    return data.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}

final merchantFinanceRepositoryProvider = Provider<MerchantFinanceRepository>(
  (ref) => ApiMerchantFinanceRepository(),
);

final merchantFinanceProvider = FutureProvider.autoDispose
    .family<MerchantFinanceData, String>(
      (ref, businessId) =>
          ref.watch(merchantFinanceRepositoryProvider).load(businessId),
    );
