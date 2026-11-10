class DeliveryLocality {
  final String id;
  final String name;
  final bool deliveryEnabled;

  const DeliveryLocality({
    required this.id,
    required this.name,
    required this.deliveryEnabled,
  });

  factory DeliveryLocality.fromJson(Map<String, dynamic> json) =>
      DeliveryLocality(
        id: json['id'] as String,
        name: json['name'] as String,
        deliveryEnabled: json['delivery_enabled'] as bool? ?? false,
      );
}

class DeliveryDistrict {
  final String id;
  final String name;
  final List<DeliveryLocality> localities;

  const DeliveryDistrict({
    required this.id,
    required this.name,
    required this.localities,
  });

  factory DeliveryDistrict.fromJson(Map<String, dynamic> json) =>
      DeliveryDistrict(
        id: json['id'] as String,
        name: json['name'] as String,
        localities: (json['localities'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DeliveryLocality.fromJson)
            .toList(growable: false),
      );
}

class PlatformCatalogCategory {
  final String id;
  final String vertical;
  final String slug;
  final String name;
  final String? parentId;
  final int sortOrder;

  const PlatformCatalogCategory({
    required this.id,
    required this.vertical,
    required this.slug,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
  });

  factory PlatformCatalogCategory.fromJson(Map<String, dynamic> json) =>
      PlatformCatalogCategory(
        id: json['id'] as String,
        vertical: json['vertical'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        parentId: json['parent_id'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class PlatformCatalogVariant {
  final String id;
  final String name;
  final String unitLabel;
  final int priceMinor;
  final String currency;
  final int priceRevision;
  final bool isActive;

  const PlatformCatalogVariant({
    required this.id,
    required this.name,
    required this.unitLabel,
    required this.priceMinor,
    required this.currency,
    required this.priceRevision,
    this.isActive = true,
  });

  factory PlatformCatalogVariant.fromJson(Map<String, dynamic> json) =>
      PlatformCatalogVariant(
        id: json['id'] as String,
        name: json['name'] as String,
        unitLabel: json['unit_label'] as String? ?? '',
        priceMinor: (json['price_minor'] as num?)?.toInt() ?? 0,
        currency: json['currency'] as String? ?? 'INR',
        priceRevision: (json['price_revision'] as num?)?.toInt() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );
}

class PlatformCatalogProduct {
  final String id;
  final String sku;
  final String categoryId;
  final String categoryName;
  final String categorySlug;
  final String vertical;
  final String name;
  final String description;
  final List<String> imageUrls;
  final List<PlatformCatalogVariant> variants;

  const PlatformCatalogProduct({
    required this.id,
    required this.sku,
    required this.categoryId,
    required this.categoryName,
    required this.categorySlug,
    required this.vertical,
    required this.name,
    required this.description,
    this.imageUrls = const [],
    this.variants = const [],
  });

  factory PlatformCatalogProduct.fromJson(Map<String, dynamic> json) =>
      PlatformCatalogProduct(
        id: json['id'] as String,
        sku: json['sku'] as String? ?? '',
        categoryId: json['category_id'] as String,
        categoryName: json['category_name'] as String? ?? '',
        categorySlug: json['category_slug'] as String? ?? '',
        vertical: json['vertical'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        imageUrls: (json['image_urls'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        variants: (json['variants'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlatformCatalogVariant.fromJson)
            .toList(growable: false),
      );

  int? get lowestPriceMinor {
    if (variants.isEmpty) return null;
    return variants
        .map((variant) => variant.priceMinor)
        .reduce((left, right) => left < right ? left : right);
  }
}
