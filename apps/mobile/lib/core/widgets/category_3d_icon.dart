import 'package:flutter/material.dart';

import '../theme/abashyaka_colors.dart';

/// Renders a category icon with 3D styling or asset support.
class Category3DIcon extends StatelessWidget {
  final String categoryId;
  final double size;

  const Category3DIcon({super.key, required this.categoryId, this.size = 44.0});

  @override
  Widget build(BuildContext context) {
    final assetPath = _getAssetPath(categoryId);
    if (assetPath != null) {
      return Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(categoryId),
      );
    }
    return _buildFallbackIcon(categoryId);
  }

  String? _getAssetPath(String id) {
    final lower = id.toLowerCase();
    if (lower.contains('food'))
      return 'assets/abashyaka/categories/cat_food_delivery.png';
    if (lower.contains('groc'))
      return 'assets/abashyaka/categories/cat_grocery_essentials.png';
    if (lower.contains('shop'))
      return 'assets/abashyaka/categories/cat_local_shops.png';
    if (lower.contains('serv'))
      return 'assets/abashyaka/categories/cat_home_services.png';
    if (lower.contains('pharm') || lower.contains('health'))
      return 'assets/abashyaka/categories/cat_pharmacy_health.png';
    if (lower.contains('all') || lower.contains('more'))
      return 'assets/abashyaka/categories/cat_all_categories.png';
    return null;
  }

  Widget _buildFallbackIcon(String id) {
    final lower = id.toLowerCase();
    IconData iconData = Icons.category_rounded;
    Color iconColor = AbashyakaColors.metallicTeal;

    if (lower.contains('food')) {
      iconData = Icons.lunch_dining_rounded;
      iconColor = const Color(0xFFF59E0B);
    } else if (lower.contains('groc')) {
      iconData = Icons.shopping_basket_rounded;
      iconColor = const Color(0xFF10B981);
    } else if (lower.contains('shop')) {
      iconData = Icons.storefront_rounded;
      iconColor = const Color(0xFFEC4899);
    } else if (lower.contains('serv')) {
      iconData = Icons.build_rounded;
      iconColor = const Color(0xFF008C95);
    } else if (lower.contains('pharm') ||
        lower.contains('health') ||
        lower.contains('doc')) {
      iconData = Icons.medical_services_rounded;
      iconColor = const Color(0xFF00B3AE);
    } else if (lower.contains('elect')) {
      iconData = Icons.headphones_rounded;
      iconColor = const Color(0xFF6366F1);
    } else if (lower.contains('home')) {
      iconData = Icons.home_repair_service_rounded;
      iconColor = const Color(0xFFF97316);
    } else if (lower.contains('more') || lower.contains('all')) {
      iconData = Icons.grid_view_rounded;
      iconColor = AbashyakaColors.metallicTeal;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(iconData, size: size * 0.58, color: iconColor),
      ),
    );
  }
}
