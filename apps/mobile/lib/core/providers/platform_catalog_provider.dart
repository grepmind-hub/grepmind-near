import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/platform_catalog.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PlatformCatalogQuery {
  final String vertical;
  final String city;
  final String locality;
  final String localityId;
  final String search;
  final String? categoryId;

  const PlatformCatalogQuery({
    required this.vertical,
    required this.city,
    this.locality = '',
    this.localityId = '',
    this.search = '',
    this.categoryId,
  });

  Map<String, dynamic> get parameters => {
    'vertical': vertical,
    'city': city,
    if (localityId.isNotEmpty) 'locality_id': localityId,
  };

  @override
  bool operator ==(Object other) =>
      other is PlatformCatalogQuery &&
      vertical == other.vertical &&
      city == other.city &&
      locality == other.locality &&
      localityId == other.localityId &&
      search == other.search &&
      categoryId == other.categoryId;

  @override
  int get hashCode =>
      Object.hash(vertical, city, locality, localityId, search, categoryId);
}

final platformDeliveryLocationsProvider =
    FutureProvider.autoDispose<List<DeliveryDistrict>>((ref) async {
      return ref.read(platformCatalogRepositoryProvider).locations();
    });

class DeliveryLocationSelection {
  final String district;
  final String localityId;
  final String locality;
  const DeliveryLocationSelection({
    required this.district,
    required this.localityId,
    required this.locality,
  });
}

class DeliveryLocationStorage {
  static const _districtKey = 'orders_delivery_district';
  static const _localityIdKey = 'orders_delivery_locality_id';
  static const _localityKey = 'orders_delivery_locality_name';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<DeliveryLocationSelection?> read() async {
    final values = await Future.wait([
      _storage.read(key: _districtKey),
      _storage.read(key: _localityIdKey),
      _storage.read(key: _localityKey),
    ]);
    if (values[0] == null) {
      return null;
    }
    return DeliveryLocationSelection(
      district: values[0]!,
      localityId: values[1] ?? '',
      locality: values[2] ?? '',
    );
  }

  Future<void> write(DeliveryLocationSelection value) async {
    await Future.wait([
      _storage.write(key: _districtKey, value: value.district),
      _storage.write(key: _localityIdKey, value: value.localityId),
      _storage.write(key: _localityKey, value: value.locality),
    ]);
  }

  Future<void> writeDistrict(String district) async {
    await Future.wait([
      _storage.write(key: _districtKey, value: district),
      _storage.delete(key: _localityIdKey),
      _storage.delete(key: _localityKey),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _districtKey),
      _storage.delete(key: _localityIdKey),
      _storage.delete(key: _localityKey),
    ]);
  }
}

final deliveryLocationStorageProvider = Provider<DeliveryLocationStorage>(
  (ref) => DeliveryLocationStorage(),
);

class PlatformCatalogPage {
  final List<PlatformCatalogProduct> products;
  final bool hasMore;
  final int count;
  final bool deliveryAvailable;

  const PlatformCatalogPage({
    required this.products,
    required this.hasMore,
    required this.count,
    this.deliveryAvailable = true,
  });
}

class PlatformCatalogRepository {
  Future<List<DeliveryDistrict>> locations() async {
    final response = await apiClient.get('/catalog/locations');
    final rows =
        (response.data as Map<String, dynamic>)['data'] as List? ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(DeliveryDistrict.fromJson)
        .toList(growable: false);
  }

  Future<List<PlatformCatalogCategory>> categories(
    PlatformCatalogQuery query,
  ) async {
    final response = await apiClient.get(
      '/catalog/categories',
      queryParameters: query.parameters,
    );
    final data = (response.data as Map<String, dynamic>)['data'] as List? ?? [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(PlatformCatalogCategory.fromJson)
        .toList(growable: false);
  }

  Future<PlatformCatalogPage> products(
    PlatformCatalogQuery query, {
    int offset = 0,
  }) async {
    final response = await apiClient.get(
      '/catalog/products',
      queryParameters: {
        ...query.parameters,
        if (query.search.trim().isNotEmpty) 'q': query.search.trim(),
        if (query.categoryId != null) 'category_id': query.categoryId,
        'limit': 20,
        'offset': offset,
      },
    );
    final envelope = response.data as Map<String, dynamic>;
    final rows = envelope['data'] as List? ?? [];
    final meta = envelope['meta'] as Map<String, dynamic>? ?? const {};
    return PlatformCatalogPage(
      products: rows
          .whereType<Map<String, dynamic>>()
          .map(PlatformCatalogProduct.fromJson)
          .toList(growable: false),
      hasMore: meta['has_more'] as bool? ?? false,
      count: (meta['count'] as num?)?.toInt() ?? rows.length,
      deliveryAvailable: meta['delivery_available'] as bool? ?? true,
    );
  }

  Future<PlatformCatalogProduct> product(
    String id,
    PlatformCatalogQuery query,
  ) async {
    final response = await apiClient.get(
      '/catalog/products/$id',
      queryParameters: query.parameters,
    );
    return PlatformCatalogProduct.fromJson(
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>,
    );
  }
}

final platformCatalogRepositoryProvider = Provider<PlatformCatalogRepository>(
  (ref) => PlatformCatalogRepository(),
);

final platformCatalogCategoriesProvider = FutureProvider.autoDispose
    .family<List<PlatformCatalogCategory>, PlatformCatalogQuery>(
      (ref, query) =>
          ref.read(platformCatalogRepositoryProvider).categories(query),
    );

final platformCatalogProductsProvider = FutureProvider.autoDispose
    .family<PlatformCatalogPage, PlatformCatalogQuery>(
      (ref, query) =>
          ref.read(platformCatalogRepositoryProvider).products(query),
    );

final platformCatalogProductProvider = FutureProvider.autoDispose
    .family<PlatformCatalogProduct, ({String id, PlatformCatalogQuery query})>(
      (ref, key) => ref
          .read(platformCatalogRepositoryProvider)
          .product(key.id, key.query),
    );

String platformCatalogErrorMessage(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Catalog is offline. Check your connection and retry.';
    }
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final details = body['error'];
      if (details is Map<String, dynamic> && details['message'] is String) {
        return details['message'] as String;
      }
    }
  }
  return 'Catalog could not be loaded. Please try again.';
}
