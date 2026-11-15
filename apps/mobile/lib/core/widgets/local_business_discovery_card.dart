import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/category_placeholder.dart';
import 'package:url_launcher/url_launcher.dart';

/// Local business discovery card replacing generic gray thumbnails with real storefront photography,
/// clear distance/hours, verified badges, and contextual Call/Directions/Shop actions.
class LocalBusinessDiscoveryCard extends StatelessWidget {
  const LocalBusinessDiscoveryCard({
    super.key,
    required this.name,
    required this.category,
    this.categorySlug,
    this.coverPhotoUrl,
    this.rating,
    this.reviewCount,
    this.distanceKm,
    this.locality,
    this.operatingStatus = 'Open now',
    this.isVerified = true,
    this.phoneNumber,
    this.latitude,
    this.longitude,
    this.primaryActionLabel = 'View Store',
    this.onTap,
    this.onPrimaryAction,
  });

  final String name;
  final String category;
  final String? categorySlug;
  final String? coverPhotoUrl;
  final double? rating;
  final int? reviewCount;
  final double? distanceKm;
  final String? locality;
  final String operatingStatus;
  final bool isVerified;
  final String? phoneNumber;
  final double? latitude;
  final double? longitude;
  final String primaryActionLabel;
  final VoidCallback? onTap;
  final VoidCallback? onPrimaryAction;

  Future<void> _makeCall() async {
    if (phoneNumber == null || phoneNumber!.isEmpty) return;
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openDirections() async {
    if (latitude == null || longitude == null) return;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brandBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A17352C),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Storefront Cover Image
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      coverPhotoUrl != null && coverPhotoUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: apiClient.resolveMediaUrl(coverPhotoUrl!),
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => _placeholder(),
                            )
                          : _placeholder(),
                      // Top badges overlay
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 10,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                category,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (isVerified)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.emerald,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_rounded, size: 12, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Verified',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Store Details & Metadata
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.brandText,
                            ),
                          ),
                        ),
                        if (rating != null) ...[
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 2),
                              Text(
                                rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.brandText,
                                ),
                              ),
                              if (reviewCount != null)
                                Text(
                                  ' ($reviewCount)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.brandTextMuted,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Distance, Locality, Hours row
                    Row(
                      children: [
                        if (distanceKm != null) ...[
                          const Icon(Icons.near_me_outlined, size: 14, color: AppTheme.emerald),
                          const SizedBox(width: 3),
                          Text(
                            '${distanceKm!.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.emerald,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (locality != null && locality!.isNotEmpty) ...[
                          Expanded(
                            child: Text(
                              locality!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.brandTextMuted,
                              ),
                            ),
                          ),
                        ],
                        Text(
                          operatingStatus,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: operatingStatus.toLowerCase().contains('closed')
                                ? AppTheme.error
                                : AppTheme.emerald,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Bottom Action Bar: Call / Directions / Primary CTA
                    Row(
                      children: [
                        if (phoneNumber != null && phoneNumber!.isNotEmpty)
                          IconButton(
                            onPressed: _makeCall,
                            tooltip: 'Call store',
                            icon: const Icon(Icons.phone_outlined, size: 18),
                            color: AppTheme.brandText,
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.brandCanvas,
                              minimumSize: const Size(40, 40),
                            ),
                          ),
                        if (latitude != null && longitude != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _openDirections,
                            tooltip: 'Get directions',
                            icon: const Icon(Icons.directions_outlined, size: 18),
                            color: AppTheme.brandText,
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.brandCanvas,
                              minimumSize: const Size(40, 40),
                            ),
                          ),
                        ],
                        const Spacer(),
                        ElevatedButton(
                          onPressed: onPrimaryAction ?? onTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.emerald,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            minimumSize: const Size(100, 40),
                          ),
                          child: Text(
                            primaryActionLabel,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return CategoryThemedPlaceholder(
      categorySlug: categorySlug ?? category,
      categoryName: category,
      businessName: name,
    );
  }
}
