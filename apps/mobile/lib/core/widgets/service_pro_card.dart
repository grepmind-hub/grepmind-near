import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/category_placeholder.dart';

/// Service professional card displaying verified artisan credentials, experience,
/// starting rates, service coverage, and direct appointment booking CTA.
class ServiceProCard extends StatelessWidget {
  const ServiceProCard({
    super.key,
    required this.name,
    required this.specialization,
    this.photoUrl,
    this.experienceYears,
    this.rating,
    this.jobsCompleted,
    this.startingPriceMinor,
    this.availability = 'Available today',
    this.coverageLocality,
    this.isVerified = true,
    this.onTap,
    this.onBook,
  });

  final String name;
  final String specialization;
  final String? photoUrl;
  final int? experienceYears;
  final double? rating;
  final int? jobsCompleted;
  final int? startingPriceMinor;
  final String availability;
  final String? coverageLocality;
  final bool isVerified;
  final VoidCallback? onTap;
  final VoidCallback? onBook;

  String _formatPrice(int minor) => '₹${(minor / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brandBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0817352C),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Professional Avatar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 76,
                        height: 76,
                        color: AppTheme.brandCanvas,
                        child: photoUrl != null && photoUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: apiClient.resolveMediaUrl(photoUrl!),
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => _placeholder(),
                              )
                            : _placeholder(),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Professional info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.brandText,
                                  ),
                                ),
                              ),
                              if (isVerified)
                                const Icon(Icons.verified_rounded, size: 16, color: AppTheme.emerald),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            specialization,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.emerald,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Rating and Experience badges
                          Row(
                            children: [
                              if (rating != null) ...[
                                const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 2),
                                Text(
                                  rating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.brandText,
                                  ),
                                ),
                                if (jobsCompleted != null)
                                  Text(
                                    ' ($jobsCompleted jobs)',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.brandTextMuted,
                                    ),
                                  ),
                                const SizedBox(width: 8),
                              ],
                              if (experienceYears != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.brandCanvas,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppTheme.brandBorder),
                                  ),
                                  child: Text(
                                    '$experienceYears+ yrs exp',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.brandText,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: AppTheme.brandBorder),
                const SizedBox(height: 8),

                // Bottom row: Starting fee / Availability & Book CTA
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (startingPriceMinor != null && startingPriceMinor! > 0)
                            Text(
                              'Starts at ${_formatPrice(startingPriceMinor!)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.brandText,
                              ),
                            )
                          else
                            const Text(
                              'Free quote & inspection',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.brandText,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppTheme.emerald,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                availability,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.brandTextMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: onBook ?? onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: const Size(100, 42),
                      ),
                      child: const Text(
                        'Book Service',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return CategoryThemedPlaceholder(
      categorySlug: specialization,
      categoryName: specialization,
      businessName: name,
      isAvatar: true,
    );
  }
}
