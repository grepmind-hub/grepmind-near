import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/abashyaka_colors.dart';
import '../theme/abashyaka_tokens.dart';
import '../theme/abashyaka_typography.dart';

class FloatingNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const FloatingNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// The official floating glossy bottom navigation bar for Abashyaka.
class FloatingBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FloatingNavItem> items;

  const FloatingBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 68,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
        decoration: BoxDecoration(
          color: AbashyakaColors.pureWhite,
          borderRadius: BorderRadius.circular(AbashyakaRadius.nav),
          border: Border.all(
            color: AbashyakaColors.silverGlass.withValues(alpha: 0.8),
            width: 1.2,
          ),
          boxShadow: AbashyakaShadows.floatingNav,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              _buildNavItem(context, i, items[i]),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, FloatingNavItem item) {
    final isSelected = index == currentIndex;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap(index);
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected
                    ? AbashyakaColors.iceAquaWhite
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isSelected ? item.activeIcon : item.icon,
                size: 22,
                color: isSelected
                    ? AbashyakaColors.metallicTeal
                    : AbashyakaColors.inkBlack,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: AbashyakaTypography.categoryLabel(
                fontSize: 10.5,
                color: isSelected
                    ? AbashyakaColors.metallicTeal
                    : AbashyakaColors.secondaryText,
              ).copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
