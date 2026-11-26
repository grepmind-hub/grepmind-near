import 'package:flutter/material.dart';

import '../theme/abashyaka_colors.dart';

/// Renders a category icon with 3D styling or asset support.
/// Maps all 18 Abashyaka Top-Level Categories to official 3D assets
/// with graceful fallback to styled vector glyphs.
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
    // 1. Food
    if (lower.contains('food') || lower.contains('restaurant')) {
      return 'assets/icons/categories/food.webp';
    }
    // 2. Grocery
    if (lower.contains('groc')) {
      return 'assets/icons/categories/grocery.webp';
    }
    // 3. Medicines
    if (lower.contains('medicin') || lower.contains('pharm')) {
      return 'assets/icons/categories/medicines.webp';
    }
    // 4. Doctors
    if (lower.contains('doctor') || lower.contains('clinic')) {
      return 'assets/icons/categories/doctors.webp';
    }
    // 5. Cab & Auto
    if (lower.contains('cab') ||
        lower.contains('auto') ||
        lower.contains('taxi')) {
      return 'assets/icons/categories/cab_auto.webp';
    }
    // 6. Services (Electrician, Plumber, Carpenter, AC, Home Painting, Cleaning)
    if (lower.contains('serv') ||
        lower.contains('plumb') ||
        lower.contains('elect') ||
        lower.contains('carpent') ||
        lower.contains('clean') ||
        lower.contains('paint')) {
      return 'assets/icons/categories/services.webp';
    }
    // 7. Electronics
    if (lower.contains('electr') ||
        lower.contains('gadget') ||
        lower.contains('device')) {
      return 'assets/icons/categories/electronics.webp';
    }
    // 8. Shops (General Store, Tailoring, Stationery, Gifting)
    if (lower.contains('shop') ||
        lower.contains('retail') ||
        lower.contains('general') ||
        lower.contains('tailor')) {
      return 'assets/icons/categories/shops.webp';
    }
    // 9. Fashion
    if (lower.contains('fashion') ||
        lower.contains('cloth') ||
        lower.contains('boutique')) {
      return 'assets/icons/categories/fashion.webp';
    }
    // 10. Hotels & Stays
    if (lower.contains('hotel') ||
        lower.contains('stay') ||
        lower.contains('lodge')) {
      return 'assets/icons/categories/hotels_stays.webp';
    }
    // 11. Fitness & Wellness
    if (lower.contains('fit') ||
        lower.contains('gym') ||
        lower.contains('well')) {
      return 'assets/icons/categories/fitness_wellness.webp';
    }
    // 12. Beauty & Salon
    if (lower.contains('beauty') ||
        lower.contains('salon') ||
        lower.contains('spa')) {
      return 'assets/abashyaka/categories/cat_appointments_booking.png';
    }
    // 16. Events & Catering
    if (lower.contains('event') || lower.contains('cater')) {
      return 'assets/abashyaka/categories/cat_events_local.png';
    }
    // More / All
    if (lower.contains('more') || lower.contains('all')) {
      return 'assets/icons/categories/more.webp';
    }

    return null;
  }

  Widget _buildFallbackIcon(String id) {
    final lower = id.toLowerCase();
    IconData iconData = Icons.category_rounded;
    Color iconColor = AbashyakaColors.metallicTeal;

    if (lower.contains('food') || lower.contains('restaurant')) {
      iconData = Icons.lunch_dining_rounded;
      iconColor = const Color(0xFFEA580C);
    } else if (lower.contains('groc')) {
      iconData = Icons.shopping_basket_rounded;
      iconColor = const Color(0xFF16A34A);
    } else if (lower.contains('medicin') || lower.contains('pharm')) {
      iconData = Icons.medication_rounded;
      iconColor = const Color(0xFF0284C7);
    } else if (lower.contains('doctor') || lower.contains('clinic')) {
      iconData = Icons.medical_services_rounded;
      iconColor = const Color(0xFF007D80);
    } else if (lower.contains('cab') || lower.contains('auto')) {
      iconData = Icons.local_taxi_rounded;
      iconColor = const Color(0xFFF4B942);
    } else if (lower.contains('serv')) {
      iconData = Icons.build_circle_rounded;
      iconColor = AbashyakaColors.metallicTeal;
    } else if (lower.contains('electr')) {
      iconData = Icons.devices_rounded;
      iconColor = const Color(0xFF4F46E5);
    } else if (lower.contains('shop')) {
      iconData = Icons.storefront_rounded;
      iconColor = const Color(0xFFDB2777);
    } else if (lower.contains('fashion')) {
      iconData = Icons.checkroom_rounded;
      iconColor = const Color(0xFFE11D48);
    } else if (lower.contains('hotel') || lower.contains('stay')) {
      iconData = Icons.hotel_rounded;
      iconColor = AbashyakaColors.signatureTeal;
    } else if (lower.contains('fit') || lower.contains('gym')) {
      iconData = Icons.fitness_center_rounded;
      iconColor = const Color(0xFFD97706);
    } else if (lower.contains('beauty') || lower.contains('salon')) {
      iconData = Icons.face_retouching_natural_rounded;
      iconColor = const Color(0xFFDB2777);
    } else if (lower.contains('auto')) {
      iconData = Icons.directions_car_filled_rounded;
      iconColor = AbashyakaColors.signatureTeal;
    } else if (lower.contains('edu') || lower.contains('school')) {
      iconData = Icons.school_rounded;
      iconColor = const Color(0xFF2563EB);
    } else if (lower.contains('home') || lower.contains('furnitur')) {
      iconData = Icons.chair_rounded;
      iconColor = const Color(0xFFD97706);
    } else if (lower.contains('event') || lower.contains('cater')) {
      iconData = Icons.celebration_rounded;
      iconColor = const Color(0xFFF4B942);
    } else if (lower.contains('agri') || lower.contains('farm')) {
      iconData = Icons.agriculture_rounded;
      iconColor = const Color(0xFF15803D);
    } else if (lower.contains('construct') || lower.contains('build')) {
      iconData = Icons.foundation_rounded;
      iconColor = const Color(0xFFB45309);
    } else if (lower.contains('more') || lower.contains('all')) {
      iconData = Icons.grid_view_rounded;
      iconColor = AbashyakaColors.metallicTeal;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(iconData, size: size * 0.58, color: iconColor),
      ),
    );
  }
}
