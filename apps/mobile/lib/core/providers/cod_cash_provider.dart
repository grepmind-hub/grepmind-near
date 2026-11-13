import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

abstract interface class CODStatusRepository {
  Future<Map<String, dynamic>> getCustomerStatus(String orderId);
}

final codStatusRepositoryProvider = Provider<CODStatusRepository>(
  (ref) => ApiCODStatusRepository(apiClient),
);

class ApiCODStatusRepository implements CODStatusRepository {
  const ApiCODStatusRepository(this._api);

  final ApiClient _api;

  @override
  Future<Map<String, dynamic>> getCustomerStatus(String orderId) async {
    final response = await _api.get(
      '/orders/${Uri.encodeComponent(orderId)}/cod-status',
    );
    final root = response.data as Map<String, dynamic>;
    return root['data'] as Map<String, dynamic>;
  }
}
