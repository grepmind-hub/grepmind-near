import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

/// Business listing summary (search / nearby results).
class Business extends Equatable {
  final String id;
  final String name;
  final String? slug;
  final String categorySlug;
  final String? categoryName;
  final String? categoryIcon;
  final String addressText;
  final String? locality;
  final String? city;
  final String? postalCode;
  final double? distanceM;
  final String status;
  final String verificationStatus;
  final String? phoneE164;
  final String? whatsappE164;
  final bool isOpenNow;
  final bool acceptsRequests;
  final String? coverPhotoUrl;
  final double? rating;
  final int? reviewCount;
  final double? latitude;
  final double? longitude;
  final String? description;

  const Business({
    required this.id,
    required this.name,
    this.slug,
    required this.categorySlug,
    this.categoryName,
    this.categoryIcon,
    required this.addressText,
    this.locality,
    this.city,
    this.postalCode,
    this.distanceM,
    required this.status,
    required this.verificationStatus,
    this.phoneE164,
    this.whatsappE164,
    this.isOpenNow = false,
    this.acceptsRequests = false,
    this.coverPhotoUrl,
    this.rating,
    this.reviewCount,
    this.latitude,
    this.longitude,
    this.description,
  });

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String?,
      categorySlug: json['category_slug'] as String? ?? '',
      categoryName: json['category_name'] as String?,
      categoryIcon: json['category_icon'] as String?,
      addressText: json['address_text'] as String? ?? '',
      locality: json['locality'] as String?,
      city: json['city'] as String?,
      postalCode: json['postal_code'] as String?,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'pending',
      verificationStatus: json['verification_status'] as String? ?? 'unverified',
      phoneE164: json['phone_e164'] as String?,
      whatsappE164: json['whatsapp_e164'] as String?,
      isOpenNow: json['is_open_now'] as bool? ?? false,
      acceptsRequests: json['accepts_requests'] as bool? ?? false,
      coverPhotoUrl: json['cover_photo_url'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'category_slug': categorySlug,
      'category_name': categoryName,
      'category_icon': categoryIcon,
      'address_text': addressText,
      'locality': locality,
      'city': city,
      'postal_code': postalCode,
      'distance_m': distanceM,
      'status': status,
      'verification_status': verificationStatus,
      'phone_e164': phoneE164,
      'whatsapp_e164': whatsappE164,
      'is_open_now': isOpenNow,
      'accepts_requests': acceptsRequests,
      'cover_photo_url': coverPhotoUrl,
      'rating': rating,
      'review_count': reviewCount,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
    };
  }

  String get displayAddress {
    final parts = <String>[];
    if (locality != null && locality!.isNotEmpty) parts.add(locality!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    return parts.join(', ');
  }

  String get distanceText {
    if (distanceM == null) return '';
    if (distanceM! < 1000) {
      return '${distanceM!.round()} m';
    }
    return '${(distanceM! / 1000).toStringAsFixed(1)} km';
  }

  @override
  List<Object?> get props => [
        id, name, slug, categorySlug, categoryName, categoryIcon, addressText,
        locality, city, postalCode, distanceM, status, verificationStatus,
        phoneE164, whatsappE164, isOpenNow, acceptsRequests, coverPhotoUrl,
        rating, reviewCount, latitude, longitude, description,
      ];
}

/// Full business detail.
class BusinessDetail extends Business {
  final List<BusinessHour> businessHours;
  final List<Product> products;
  final List<Offer> offers;
  final List<Service> services;
  final List<BusinessMedia> media;
  final int? serviceRadiusM;
  final int? experienceYears;
  final String? serviceDescription;
  final DateTime? nextAvailableAppointment;

  const BusinessDetail({
    required super.id,
    required super.name,
    super.slug,
    required super.categorySlug,
    super.categoryName,
    super.categoryIcon,
    required super.addressText,
    super.locality,
    super.city,
    super.postalCode,
    super.distanceM,
    required super.status,
    required super.verificationStatus,
    super.phoneE164,
    super.whatsappE164,
    super.isOpenNow,
    super.acceptsRequests,
    super.coverPhotoUrl,
    super.rating,
    super.reviewCount,
    super.latitude,
    super.longitude,
    super.description,
    this.businessHours = const [],
    this.products = const [],
    this.offers = const [],
    this.services = const [],
    this.media = const [],
    this.serviceRadiusM,
    this.experienceYears,
    this.serviceDescription,
    this.nextAvailableAppointment,
  }) : super();

  factory BusinessDetail.fromJson(Map<String, dynamic> json) {
    return BusinessDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String?,
      categorySlug: json['category_slug'] as String? ?? '',
      categoryName: json['category_name'] as String?,
      categoryIcon: json['category_icon'] as String?,
      addressText: json['address_text'] as String? ?? '',
      locality: json['locality'] as String?,
      city: json['city'] as String?,
      postalCode: json['postal_code'] as String?,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'pending',
      verificationStatus: json['verification_status'] as String? ?? 'unverified',
      phoneE164: json['phone_e164'] as String?,
      whatsappE164: json['whatsapp_e164'] as String?,
      isOpenNow: json['is_open_now'] as bool? ?? false,
      acceptsRequests: json['accepts_requests'] as bool? ?? false,
      coverPhotoUrl: json['cover_photo_url'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int?,
      description: json['description'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      businessHours: (json['business_hours'] as List<dynamic>?)
          ?.map((e) => BusinessHour.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
      products: (json['products'] as List<dynamic>?)
          ?.map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
      offers: (json['offers'] as List<dynamic>?)
          ?.map((e) => Offer.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
      services: (json['services'] as List<dynamic>?)
          ?.map((e) => Service.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
      media: (json['media'] as List<dynamic>?)
          ?.map((e) => BusinessMedia.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
      serviceRadiusM: json['service_radius_m'] as int?,
      experienceYears: json['experience_years'] as int?,
      serviceDescription: json['service_description'] as String?,
      nextAvailableAppointment: json['next_available_appointment'] != null
          ? DateTime.tryParse(json['next_available_appointment'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => super.props..addAll([
        businessHours, products, offers,
        services, media, serviceRadiusM, experienceYears, serviceDescription,
        nextAvailableAppointment,
      ]);
}

class BusinessHour extends Equatable {
  final int weekday;
  final String? opensAt;
  final String? closesAt;
  final bool isClosed;

  const BusinessHour({
    required this.weekday,
    this.opensAt,
    this.closesAt,
    this.isClosed = false,
  });

  factory BusinessHour.fromJson(Map<String, dynamic> json) {
    return BusinessHour(
      weekday: json['weekday'] as int? ?? 0,
      opensAt: json['opens_at'] as String?,
      closesAt: json['closes_at'] as String?,
      isClosed: json['is_closed'] as bool? ?? false,
    );
  }

  String get weekdayLabel {
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return labels[weekday.clamp(0, 6)];
  }

  String get timeRange {
    if (isClosed) return 'Closed';
    final open = opensAt ?? '--:--';
    final close = closesAt ?? '--:--';
    return '$open - $close';
  }

  @override
  List<Object?> get props => [weekday, opensAt, closesAt, isClosed];
}

class Product extends Equatable {
  final String id;
  final String businessId;
  final String name;
  final String? description;
  final double? price;
  final String currency;
  final String stockStatus;
  final bool isPublished;
  final String? imageUrl;
  final DateTime? updatedAt;

  const Product({
    required this.id,
    required this.businessId,
    required this.name,
    this.description,
    this.price,
    this.currency = 'INR',
    this.stockStatus = 'unknown',
    this.isPublished = false,
    this.imageUrl,
    this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      businessId: json['business_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'INR',
      stockStatus: json['stock_status'] as String? ?? 'unknown',
      isPublished: json['is_published'] as bool? ?? false,
      imageUrl: json['image_url'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  String get priceText {
    if (price == null) return 'Price on request';
    final f = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    return f.format(price!);
  }

  @override
  List<Object?> get props => [
        id, businessId, name, description, price, currency, stockStatus,
        isPublished, imageUrl, updatedAt,
      ];
}

class Offer extends Equatable {
  final String id;
  final String businessId;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final String? imageUrl;
  final String? terms;
  final int? discountPercent;
  final DateTime? createdAt;

  const Offer({
    required this.id,
    required this.businessId,
    required this.title,
    this.description,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.imageUrl,
    this.terms,
    this.discountPercent,
    this.createdAt,
  });

  factory Offer.fromJson(Map<String, dynamic> json) {
    return Offer(
      id: json['id'] as String,
      businessId: json['business_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      startsAt: DateTime.tryParse(json['starts_at'] as String) ?? DateTime.now(),
      endsAt: DateTime.tryParse(json['ends_at'] as String) ?? DateTime.now(),
      status: json['status'] as String? ?? 'draft',
      imageUrl: json['image_url'] as String?,
      terms: json['terms'] as String?,
      discountPercent: json['discount_percent'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  bool get isActive => status == 'published' &&
      DateTime.now().isAfter(startsAt) &&
      DateTime.now().isBefore(endsAt);

  String get discountText {
    if (discountPercent == null) return '';
    return '$discountPercent% off';
  }

  @override
  List<Object?> get props => [
        id, businessId, title, description, startsAt, endsAt, status, imageUrl,
        terms, discountPercent, createdAt,
      ];
}

class Service extends Equatable {
  final String id;
  final String businessId;
  final String name;
  final String? description;
  final double? indicativePriceMin;
  final double? indicativePriceMax;
  final String currency;
  final bool isActive;

  const Service({
    required this.id,
    required this.businessId,
    required this.name,
    this.description,
    this.indicativePriceMin,
    this.indicativePriceMax,
    this.currency = 'INR',
    this.isActive = true,
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] as String,
      businessId: json['business_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      indicativePriceMin: (json['indicative_price_min'] as num?)?.toDouble(),
      indicativePriceMax: (json['indicative_price_max'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'INR',
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  String get priceText {
    if (indicativePriceMin == null && indicativePriceMax == null) {
      return 'Price on request';
    }
    if (indicativePriceMin == indicativePriceMax) {
      return '₹${indicativePriceMin!.round()}';
    }
    final min = indicativePriceMin ?? 0;
    final max = indicativePriceMax ?? 0;
    return '₹${min.round()} - ₹${max.round()}';
  }

  @override
  List<Object?> get props => [
        id, businessId, name, description, indicativePriceMin, indicativePriceMax,
        currency, isActive,
      ];
}

class BusinessMedia extends Equatable {
  final String id;
  final String objectKey;
  final String mediaType;
  final int sortOrder;
  final String? url;

  const BusinessMedia({
    required this.id,
    required this.objectKey,
    required this.mediaType,
    required this.sortOrder,
    this.url,
  });

  factory BusinessMedia.fromJson(Map<String, dynamic> json) {
    return BusinessMedia(
      id: json['id'] as String,
      objectKey: json['object_key'] as String? ?? '',
      mediaType: json['media_type'] as String? ?? 'image',
      sortOrder: json['sort_order'] as int? ?? 0,
      url: json['url'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, objectKey, mediaType, sortOrder, url];
}

/// Authenticated user.
class AppUser extends Equatable {
  final String id;
  final String phoneE164;
  final String? displayName;
  final String status;
  final String preferredLanguage;
  final List<String> roles;

  const AppUser({
    required this.id,
    required this.phoneE164,
    this.displayName,
    required this.status,
    required this.preferredLanguage,
    required this.roles,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      phoneE164: json['phone_e164'] as String? ?? '',
      displayName: json['display_name'] as String?,
      status: json['status'] as String? ?? 'active',
      preferredLanguage: json['preferred_language'] as String? ?? 'en',
      roles: (json['roles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? const [],
    );
  }

  bool get isAdmin => roles.contains('admin');
  bool get isMerchant => roles.contains('merchant');
  bool get isCustomer => roles.contains('customer');

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone_e164': phoneE164,
      'display_name': displayName,
      'status': status,
      'preferred_language': preferredLanguage,
      'roles': roles,
    };
  }

  @override
  List<Object?> get props => [
        id, phoneE164, displayName, status, preferredLanguage, roles,
      ];
}

/// Category.
class Category extends Equatable {
  final String slug;
  final String name;
  final String? iconName;
  final String? description;

  const Category({
    required this.slug,
    required this.name,
    this.iconName,
    this.description,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      slug: json['slug'] as String,
      name: json['name'] as String? ?? '',
      iconName: json['icon_name'] as String?,
      description: json['description'] as String?,
    );
  }

  @override
  List<Object?> get props => [slug, name, iconName, description];
}

/// Service request.
class ServiceRequest extends Equatable {
  final String id;
  final String customerUserId;
  final String businessId;
  final String? serviceId;
  final String? slotId;
  final String description;
  final DateTime? requestedFor;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ServiceRequest({
    required this.id,
    required this.customerUserId,
    required this.businessId,
    this.serviceId,
    this.slotId,
    required this.description,
    this.requestedFor,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    return ServiceRequest(
      id: json['id'] as String,
      customerUserId: json['customer_user_id'] as String? ?? '',
      businessId: json['business_id'] as String? ?? '',
      serviceId: json['service_id'] as String?,
      slotId: json['slot_id'] as String?,
      description: json['description'] as String? ?? '',
      requestedFor: json['requested_for'] != null
          ? DateTime.tryParse(json['requested_for'] as String)
          : null,
      status: json['status'] as String? ?? 'requested',
      createdAt: DateTime.tryParse(json['created_at'] as String) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id, customerUserId, businessId, serviceId, slotId, description,
        requestedFor, status, createdAt, updatedAt,
      ];
}
