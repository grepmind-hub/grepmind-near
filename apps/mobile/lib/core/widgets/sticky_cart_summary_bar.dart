import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/platform_cart_provider.dart';
import 'package:grepmind_mobile/core/screens/platform_cart_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Floating persistent cart summary bar appearing when items exist in the customer cart.
/// Floats above the bottom navigation bar or at the screen footer, showing item count,
/// subtotal, and an instant "View Cart →" action.
class StickyCartSummaryBar extends ConsumerWidget {
  const StickyCartSummaryBar({
    super.key,
    required this.scope,
    this.bottomPadding = 12.0,
  });

  final PlatformCartScope scope;
  final double bottomPadding;

  String _money(int minor) => '₹${(minor / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(platformCartProvider(scope));

    if (!cart.loaded || cart.isEmpty) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlatformCartScreen(scope: scope),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.emerald,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x28059669),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Item count indicator badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${cart.itemCount} ${cart.itemCount == 1 ? 'item' : 'items'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Subtotal
                  Text(
                    '${_money(cart.subtotalHintMinor)} subtotal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),

                  // "View Cart" CTA with arrow
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Cart',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
