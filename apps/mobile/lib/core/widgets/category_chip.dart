import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Circular category item matching Screen 7 (Home / Explore) in the UI showcase.
class CategoryCircleItem extends StatelessWidget {
  const CategoryCircleItem({
    super.key,
    required this.label,
    required this.icon,
    this.backgroundColor,
    this.iconColor,
    this.isSelected = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color? backgroundColor;
  final Color? iconColor;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? (isSelected ? AppTheme.primary : const Color(0xFFF2F4F7));
    final fg = iconColor ?? (isSelected ? Colors.white : AppTheme.primary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: AppTheme.primary, width: 2.5)
                    : Border.all(color: Colors.transparent),
                boxShadow: [
                  BoxShadow(
                    color: (backgroundColor ?? AppTheme.primary).withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Icon(icon, size: 26, color: fg),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 64,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? AppTheme.primary : AppTheme.mainText,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal category chip with icon + label (classic pill style).
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = isSelected ? AppTheme.primary : AppTheme.surfaceVariant;
    final textColor = isSelected ? AppTheme.onPrimary : AppTheme.mainText;

    final chip = Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.primary : AppTheme.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: chip,
      ),
    );
  }
}

