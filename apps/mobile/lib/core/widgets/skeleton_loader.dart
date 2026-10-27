import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Shimmer skeleton shown while content loads.
class SkeletonLoader extends StatelessWidget {
  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 8,
    this.baseColor = AppTheme.surfaceVariant,
    this.highlightColor = AppTheme.primaryContainer,
  });

  final double width;
  final double height;
  final double radius;
  final Color baseColor;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// A row of skeletons simulating a text line (title + subtitle).
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.titleWidth = 0.55,
    this.subtitleWidth = 0.85,
    this.height = 16,
    this.gap = 12,
  });

  final double titleWidth;
  final double subtitleWidth;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLoader(width: MediaQuery.of(context).size.width * titleWidth, height: height),
        SizedBox(height: gap),
        SkeletonLoader(width: MediaQuery.of(context).size.width * subtitleWidth, height: height),
      ],
    );
  }
}

/// A grid of image skeletons (e.g. business photo grid).
class SkeletonImageGrid extends StatelessWidget {
  const SkeletonImageGrid({super.key, this.itemCount = 4, this.itemSize = 90});

  final int itemCount;
  final double itemSize;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(itemCount, (_) {
        return SkeletonLoader(width: itemSize, height: itemSize, radius: 10);
      }),
    );
  }
}
