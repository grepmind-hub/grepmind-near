import 'package:flutter/material.dart';

enum ScreenIllustration {
  discovery(0),
  search(1),
  booking(2),
  hospitality(3),
  customer(4),
  merchant(5);

  const ScreenIllustration(this.atlasIndex);

  final int atlasIndex;
}

/// A compact, screen-specific visual that reuses the Grepmind Near illustration set.
/// The source asset is a 3-by-2 atlas; clipping keeps each illustration independently
/// reusable without adding image-processing dependencies or duplicate assets.
class ScreenIllustrationCard extends StatelessWidget {
  const ScreenIllustrationCard({
    super.key,
    required this.illustration,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.compact = false,
    this.onTap,
  });

  final ScreenIllustration illustration;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = illustration.atlasIndex;
    final column = tile % 3;
    final row = tile ~/ 3;

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 94 : 116),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD6E4F5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final artSize = constraints.maxWidth < 360
              ? (compact ? 76.0 : 92.0)
              : (compact ? 88.0 : 108.0);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: EdgeInsets.fromLTRB(compact ? 14 : 16, 10, 10, 10),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: const Color(0xFF2457D6),
                      size: compact ? 21 : 23,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF17243B),
                              fontSize: compact ? 14 : 15,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF58677D),
                              fontSize: compact ? 11 : 12,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox.square(
                      dimension: artSize,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ClipRect(
                          child: Stack(
                            children: [
                              Positioned(
                                left: -column * artSize,
                                top: -row * artSize,
                                width: artSize * 3,
                                height: artSize * 2,
                                child: Image.asset(
                                  'assets/images/screen_illustrations.png',
                                  fit: BoxFit.fill,
                                  semanticLabel: '$title illustration',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
