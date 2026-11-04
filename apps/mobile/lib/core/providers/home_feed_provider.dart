import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

class HomeFeed {
  const HomeFeed({
    this.offers = const [],
    this.openNow = const [],
    this.services = const [],
    this.newArrivals = const [],
  });

  final List<HomeOffer> offers;
  final List<Business> openNow;
  final List<Business> services;
  final List<HomeCatalogItem> newArrivals;
}

class HomeCatalogItem {
  const HomeCatalogItem({
    required this.id,
    required this.type,
    required this.businessId,
    required this.businessName,
    required this.city,
    required this.categoryName,
    required this.name,
    required this.currency,
    required this.publishedAt,
    this.locality,
    this.description,
    this.price,
    this.priceMax,
    this.imageUrl,
  });

  final String id;
  final String type;
  final String businessId;
  final String businessName;
  final String city;
  final String categoryName;
  final String name;
  final String currency;
  final DateTime publishedAt;
  final String? locality;
  final String? description;
  final double? price;
  final double? priceMax;
  final String? imageUrl;

  factory HomeCatalogItem.fromJson(Map<String, dynamic> json) =>
      HomeCatalogItem(
        id: json['id'] as String,
        type: json['item_type'] as String,
        businessId: json['business_id'] as String,
        businessName: json['business_name'] as String,
        city: json['business_city'] as String,
        categoryName: json['category_name'] as String,
        name: json['name'] as String,
        currency: json['currency'] as String? ?? 'INR',
        publishedAt: DateTime.parse(json['published_at'] as String),
        locality: json['business_locality'] as String?,
        description: json['description'] as String?,
        price: (json['price'] as num?)?.toDouble(),
        priceMax: (json['price_max'] as num?)?.toDouble(),
        imageUrl: json['image_url'] as String?,
      );
}

class HomeOffer {
  const HomeOffer({
    required this.id,
    required this.businessId,
    required this.title,
    required this.businessName,
    required this.city,
    this.locality,
    this.description,
    this.imageUrl,
    this.businessPhotoUrl,
    this.discountPercent,
    this.endsAt,
  });

  final String id;
  final String businessId;
  final String title;
  final String businessName;
  final String city;
  final String? locality;
  final String? description;
  final String? imageUrl;
  final String? businessPhotoUrl;
  final int? discountPercent;
  final DateTime? endsAt;

  factory HomeOffer.fromJson(Map<String, dynamic> json) => HomeOffer(
    id: json['id'] as String,
    businessId: json['business_id'] as String,
    title: json['title'] as String,
    businessName: json['business_name'] as String,
    city: json['business_city'] as String,
    locality: json['business_locality'] as String?,
    description: json['description'] as String?,
    imageUrl: json['image_url'] as String?,
    businessPhotoUrl: json['business_photo_url'] as String?,
    discountPercent: json['discount_percent'] as int?,
    endsAt: DateTime.tryParse(json['ends_at'] as String? ?? ''),
  );
}

/// Isolated city feed so Home and Explore cannot overwrite each other's query state.
final homeFeedProvider = FutureProvider.family<HomeFeed, String>((
  ref,
  city,
) async {
  if (city.isEmpty) return const HomeFeed();
  final responses = await Future.wait([
    apiClient.get('/offers', queryParameters: {'city': city, 'limit': 8}),
    apiClient.get(
      '/catalog/new-arrivals',
      queryParameters: {'city': city, 'type': 'all', 'limit': 8},
    ),
    apiClient.get(
      '/businesses',
      queryParameters: {
        'city': city,
        'open_now': true,
        'sort': 'recent',
        'limit': 6,
      },
    ),
    apiClient.get(
      '/businesses',
      queryParameters: {
        'city': city,
        'available_now': true,
        'sort': 'recent',
        'limit': 6,
      },
    ),
  ]);
  List<dynamic> rows(int index) =>
      (responses[index].data as Map<String, dynamic>)['data']
          as List<dynamic>? ??
      const [];
  List<Business> businesses(int index) =>
      rows(index)
          .map((item) => Business.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
  return HomeFeed(
    offers: rows(0)
        .map((item) => HomeOffer.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    newArrivals: rows(1)
        .map((item) => HomeCatalogItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    openNow: businesses(2),
    services: businesses(3),
  );
});

final recentlyAddedBusinessesProvider =
    FutureProvider.family<List<Business>, String>((ref, city) async {
      if (city.isEmpty) return const [];
      final response = await apiClient.get(
        '/businesses',
        queryParameters: {'city': city, 'sort': 'recent', 'limit': 6},
      );
      final data = response.data as Map<String, dynamic>;
      return (data['data'] as List<dynamic>? ?? const [])
          .map((item) => Business.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    });
