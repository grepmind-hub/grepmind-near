import 'package:flutter/material.dart';

import '../theme/abashyaka_colors.dart';
import '../theme/abashyaka_tokens.dart';
import '../theme/abashyaka_typography.dart';

/// The official glossy search bar for the Abashyaka Home and Search screens.
class PremiumSearchBar extends StatelessWidget {
  final String hintText;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;
  final bool readOnly;
  final VoidCallback? onMicTap;
  final Key? searchKey;

  const PremiumSearchBar({
    super.key,
    this.hintText = 'Search shops, services, food...',
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.readOnly = false,
    this.onMicTap,
    this.searchKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: searchKey,
      height: 48,
      decoration: BoxDecoration(
        color: AbashyakaColors.pureWhite,
        borderRadius: BorderRadius.circular(AbashyakaRadius.search),
        border: Border.all(
          color: AbashyakaColors.silverGlass.withValues(alpha: 0.8),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A003F46),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AbashyakaRadius.search),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: AbashyakaColors.secondaryText,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: readOnly
                      ? Text(
                          hintText,
                          style: AbashyakaTypography.bodyMedium(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : TextField(
                          controller: controller,
                          onChanged: onChanged,
                          onSubmitted: onSubmitted,
                          cursorColor: AbashyakaColors.metallicTeal,
                          style: AbashyakaTypography.bodyLarge(fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: hintText,
                            hintStyle: AbashyakaTypography.bodyMedium(),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                ),
                if (onMicTap != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onMicTap,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.mic_none_rounded,
                        color: AbashyakaColors.secondaryText,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
