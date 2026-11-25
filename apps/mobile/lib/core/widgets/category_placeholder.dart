import 'package:flutter/material.dart';

/// Configuration for category-specific visual theme.
class CategoryThemeConfig {
  final List<Color> gradient;
  final Color accent;
  final IconData icon;

  const CategoryThemeConfig({
    required this.gradient,
    required this.accent,
    required this.icon,
  });
}

/// Provides 2026 Mint + Emerald aesthetic pastel placeholder graphics
/// replacing generic gray boxes with category-tailored gradients, ambient emblems,
/// and frosted iconography.
class CategoryThemedPlaceholder extends StatelessWidget {
  const CategoryThemedPlaceholder({
    super.key,
    this.categorySlug,
    this.categoryName,
    this.businessName,
    this.isAvatar = false,
  });

  final String? categorySlug;
  final String? categoryName;
  final String? businessName;
  final bool isAvatar;

  static CategoryThemeConfig resolveTheme(String? slug) {
    final s = slug?.toLowerCase().trim() ?? '';
    if (s.contains('grocer') ||
        s.contains('kirana') ||
        s.contains('supermarket')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
        accent: Color(0xFF16A34A),
        icon: Icons.local_grocery_store_rounded,
      );
    }
    if (s.contains('med') ||
        s.contains('pharm') ||
        s.contains('clinic') ||
        s.contains('health')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFF0FDFA), Color(0xFFCCFBF1)],
        accent: Color(0xFF0D9488),
        icon: Icons.local_pharmacy_rounded,
      );
    }
    if (s.contains('hard') ||
        s.contains('tool') ||
        s.contains('paint') ||
        s.contains('build')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
        accent: Color(0xFFD97706),
        icon: Icons.build_rounded,
      );
    }
    if (s.contains('rest') ||
        s.contains('food') ||
        s.contains('cafe') ||
        s.contains('bake') ||
        s.contains('dine')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
        accent: Color(0xFFEA580C),
        icon: Icons.restaurant_rounded,
      );
    }
    if (s.contains('electr')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFFEFCE8), Color(0xFFFEF08A)],
        accent: Color(0xFFCA8A04),
        icon: Icons.bolt_rounded,
      );
    }
    if (s.contains('plumb')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFF0F9FF), Color(0xFFE0F2FE)],
        accent: Color(0xFF0284C7),
        icon: Icons.plumbing_rounded,
      );
    }
    if (s.contains('carpent')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFFAF5FF), Color(0xFFF3E8FF)],
        accent: Color(0xFF9333EA),
        icon: Icons.carpenter_rounded,
      );
    }
    if (s.contains('tailor')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFF5F3FF), Color(0xFFEDE9FE)],
        accent: Color(0xFF7C3AED),
        icon: Icons.design_services_rounded,
      );
    }
    if (s.contains('salon') || s.contains('beauty') || s.contains('parlour')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFFDF2F8), Color(0xFFFCE7F3)],
        accent: Color(0xFFDB2777),
        icon: Icons.face_retouching_natural_rounded,
      );
    }
    if (s.contains('hotel') || s.contains('stay') || s.contains('resort')) {
      return const CategoryThemeConfig(
        gradient: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
        accent: Color(0xFF4F46E5),
        icon: Icons.hotel_rounded,
      );
    }
    // Default platform aesthetic: Fresh Emerald mint
    return const CategoryThemeConfig(
      gradient: [Color(0xFFF8FAF9), Color(0xFFE1EBE5)],
      accent: Color(0xFF059669),
      icon: Icons.storefront_rounded,
    );
  }

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return words[0].substring(0, words[0].length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = resolveTheme(categorySlug ?? categoryName);

    if (isAvatar) {
      final initials = _getInitials(businessName);
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: theme.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: initials.isNotEmpty
              ? Text(
                  initials,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: theme.accent,
                    letterSpacing: -0.5,
                  ),
                )
              : Icon(theme.icon, size: 32, color: theme.accent),
        ),
      );
    }

    // Wide Cover / Storefront Banner Placeholder
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: theme.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background ambient watermark icon
          Positioned(
            right: -16,
            bottom: -20,
            child: Icon(
              theme.icon,
              size: 130,
              color: theme.accent.withValues(alpha: 0.12),
            ),
          ),
          // Center subtle frosted emblem
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.82),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.accent.withValues(alpha: 0.20),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.accent.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(theme.icon, size: 36, color: theme.accent),
            ),
          ),
        ],
      ),
    );
  }
}
