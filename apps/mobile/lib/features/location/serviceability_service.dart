import 'package:grepmind_mobile/core/network/api_client.dart';

class ServiceabilityCapabilities {
  final bool foodDelivery;
  final bool groceryDelivery;
  final bool medicinesDelivery;
  final bool localServices;
  final bool transport;
  final bool merchantDiscovery;

  const ServiceabilityCapabilities({
    this.foodDelivery = true,
    this.groceryDelivery = true,
    this.medicinesDelivery = true,
    this.localServices = true,
    this.transport = true,
    this.merchantDiscovery = true,
  });

  factory ServiceabilityCapabilities.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ServiceabilityCapabilities();
    return ServiceabilityCapabilities(
      foodDelivery: json['food_delivery'] as bool? ?? true,
      groceryDelivery: json['grocery_delivery'] as bool? ?? true,
      medicinesDelivery: json['medicines_delivery'] as bool? ?? true,
      localServices: json['local_services'] as bool? ?? true,
      transport: json['transport'] as bool? ?? true,
      merchantDiscovery: json['merchant_discovery'] as bool? ?? true,
    );
  }
}

class ServiceabilityResult {
  final bool serviceable;
  final String status; // "active", "coming_soon", "outside_service_area"
  final String localityId;
  final String localityName;
  final String districtName;
  final String pinCode;
  final String message;
  final double? distanceKm;
  final ServiceabilityCapabilities capabilities;

  const ServiceabilityResult({
    required this.serviceable,
    required this.status,
    this.localityId = '',
    this.localityName = '',
    this.districtName = '',
    this.pinCode = '',
    this.message = '',
    this.distanceKm,
    this.capabilities = const ServiceabilityCapabilities(),
  });

  factory ServiceabilityResult.fromJson(Map<String, dynamic> json) {
    return ServiceabilityResult(
      serviceable: json['serviceable'] as bool? ?? false,
      status: json['status'] as String? ?? 'outside_service_area',
      localityId: json['locality_id'] as String? ?? '',
      localityName: json['locality_name'] as String? ?? '',
      districtName: json['district_name'] as String? ?? '',
      pinCode: json['pin_code'] as String? ?? '',
      message: json['message'] as String? ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      capabilities: ServiceabilityCapabilities.fromJson(
        json['capabilities'] as Map<String, dynamic>?,
      ),
    );
  }
}

class LocalitySummary {
  final String id;
  final String name;
  final String districtName;
  final bool deliveryEnabled;
  final List<String> pinCodes;
  final double? latitude;
  final double? longitude;

  const LocalitySummary({
    required this.id,
    required this.name,
    required this.districtName,
    required this.deliveryEnabled,
    this.pinCodes = const [],
    this.latitude,
    this.longitude,
  });
}

class ServiceabilityService {
  final ApiClient _client = ApiClient();

  Future<ServiceabilityResult> checkServiceability({
    String? pinCode,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await _client.dio.post(
        '/serviceability/check',
        data: {
          if (pinCode != null && pinCode.trim().isNotEmpty)
            'pin_code': pinCode.trim(),
          'latitude': ?latitude,
          'longitude': ?longitude,
        },
      );
      final data = response.data['data'] as Map<String, dynamic>;
      return ServiceabilityResult.fromJson(data);
    } catch (e) {
      // Fallback check if API is unreachable or fails
      final pin = pinCode?.trim() ?? '';
      if (pin == '754023') {
        return const ServiceabilityResult(
          serviceable: true,
          status: 'active',
          localityId: '02200000-0000-4000-8000-000000000201',
          localityName: 'Chhatia',
          districtName: 'Jajpur',
          pinCode: '754023',
          message: 'Active delivery hub.',
        );
      } else if (pin == '754204' || pin == '754200') {
        return const ServiceabilityResult(
          serviceable: true,
          status: 'active',
          localityId: '02200000-0000-4000-8000-000000000101',
          localityName: 'Kuanpal',
          districtName: 'Cuttack',
          pinCode: '754204',
          message: 'Active delivery hub.',
        );
      }
      return ServiceabilityResult(
        serviceable: false,
        status: 'outside_service_area',
        pinCode: pin,
        message: "We're not in your area just yet. Abashyaka is expanding neighbourhood by neighbourhood.",
      );
    }
  }

  Future<List<LocalitySummary>> fetchServiceableLocalities() async {
    try {
      final response = await _client.dio.get('/serviceability/locations');
      final data = response.data['data'] as List<dynamic>? ?? [];
      final List<LocalitySummary> results = [];
      for (final district in data) {
        final dName = district['name'] as String? ?? 'Odisha';
        final localities = district['localities'] as List<dynamic>? ?? [];
        for (final loc in localities) {
          final id = loc['id'] as String? ?? '';
          final name = loc['name'] as String? ?? '';
          final deliveryEnabled = loc['delivery_enabled'] as bool? ?? false;
          final pinCodes =
              (loc['pin_codes'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          results.add(
            LocalitySummary(
              id: id,
              name: name,
              districtName: dName,
              deliveryEnabled: deliveryEnabled,
              pinCodes: pinCodes,
              latitude: (loc['latitude'] as num?)?.toDouble(),
              longitude: (loc['longitude'] as num?)?.toDouble(),
            ),
          );
        }
      }
      return results;
    } catch (_) {
      // Offline fallback
      return const [
        LocalitySummary(
          id: '02200000-0000-4000-8000-000000000201',
          name: 'Chhatia',
          districtName: 'Jajpur',
          deliveryEnabled: true,
          pinCodes: ['754023'],
          latitude: 20.6105,
          longitude: 86.0270,
        ),
        LocalitySummary(
          id: '02200000-0000-4000-8000-000000000101',
          name: 'Kuanpal',
          districtName: 'Cuttack',
          deliveryEnabled: true,
          pinCodes: ['754204', '754200'],
          latitude: 20.5348,
          longitude: 86.0827,
        ),
        LocalitySummary(
          id: '02200000-0000-4000-8000-000000000102',
          name: 'Jagatpur',
          districtName: 'Cuttack',
          deliveryEnabled: false,
          pinCodes: ['754021'],
          latitude: 20.5100,
          longitude: 85.9200,
        ),
        LocalitySummary(
          id: '02200000-0000-4000-8000-000000000103',
          name: 'Tangi',
          districtName: 'Cuttack',
          deliveryEnabled: false,
          pinCodes: ['754022'],
          latitude: 20.5800,
          longitude: 85.9800,
        ),
        LocalitySummary(
          id: '02200000-0000-4000-8000-000000000202',
          name: 'Chandikhol',
          districtName: 'Jajpur',
          deliveryEnabled: false,
          pinCodes: ['755044'],
          latitude: 20.6900,
          longitude: 86.1500,
        ),
      ];
    }
  }

  Future<bool> notifyInterest({
    required String pinCode,
    required String localityName,
    String? phone,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _client.dio.post(
        '/serviceability/notify-interest',
        data: {
          'pin_code': pinCode,
          'locality_name': localityName,
          'notification_phone': phone ?? '',
          'latitude': ?latitude,
          'longitude': ?longitude,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
