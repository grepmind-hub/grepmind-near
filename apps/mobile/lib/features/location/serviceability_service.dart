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
  final String status;
  bool get isUnavailable => status == 'unavailable';
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
    final status = json['status'];
    final serviceable = json['serviceable'];
    if (!((serviceable == true &&
            (status == 'active' || status == 'coming_soon')) ||
        (serviceable == false && status == 'outside_service_area'))) {
      throw const FormatException('Invalid coverage decision');
    }
    return ServiceabilityResult(
      serviceable: serviceable as bool,
      status: status as String,
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
    } catch (_) {
      return const ServiceabilityResult(
        serviceable: false,
        status: 'unavailable',
      );
    }
  }

  Future<List<LocalitySummary>> fetchServiceableLocalities() async {
    final response = await _client.dio.get('/serviceability/locations');
    final data = response.data['data'] as List<dynamic>;
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
