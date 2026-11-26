import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/widgets/skeleton_loader.dart';

/// Shared cached network image widget with a shimmer skeleton placeholder
/// and configurable error fallback.
class PremiumNetworkImage extends StatelessWidget {
  const PremiumNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholderRadius = 0,
    this.errorWidget,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double placeholderRadius;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, _) => SkeletonLoader(
        width: width ?? double.infinity,
        height: height ?? double.infinity,
        radius: placeholderRadius,
      ),
      errorWidget: (_, _, _) =>
          errorWidget ??
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
