import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

class HomeFeed {
  const HomeFeed({
    this.offers = const [],
    this.openNow = const [],
    this.services = const [],
    this.recentlyAdded = const [],
  });

  final List<HomeOffer> offers;
  final List<Business> openNow;
  final List<Business> services;
  final List<Business> recentlyAdded;
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
    apiClient.get(
      '/businesses',
      queryParameters: {'city': city, 'sort': 'recent', 'limit': 6},
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
    openNow: businesses(1),
    services: businesses(2),
    recentlyAdded: businesses(3),
  );
});
