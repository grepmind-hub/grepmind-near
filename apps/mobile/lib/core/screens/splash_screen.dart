import 'package:flutter/material.dart';
import 'package:grepmind_mobile/features/branding/abashyaka_theme.dart';

/// Displays the approved flat artwork while the app restores its session.
/// The app root owns navigation and never waits for this animation.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Theme(
      data: AbashyakaTheme.theme(context),
      child: Scaffold(
        backgroundColor: AbashyakaTheme.warmWhite,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AbashyakaTheme.mint,
                Color(0xFFFFFDF8),
                AbashyakaTheme.warmWhite,
              ],
              stops: [0, .35, 1],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final landscapeHeight = constraints.maxWidth / 3;
                final contentHeight = (constraints.maxHeight - landscapeHeight)
                    .clamp(0.0, double.infinity);
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Image.asset(
                        AbashyakaTheme.splashLandscape,
                        width: constraints.maxWidth,
                        height: landscapeHeight,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        cacheWidth: 1080,
                      ),
                    ),
                    Positioned.fill(
                      bottom: landscapeHeight,
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: contentHeight),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                begin: reducedMotion ? 1 : 0,
                                end: 1,
                              ),
                              duration: reducedMotion
                                  ? Duration.zero
                                  : AbashyakaTheme.entrance,
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 8 * (1 - value)),
                                  child: child,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    AbashyakaTheme.splashEmblem,
                                    height: (constraints.maxHeight * .22).clamp(
                                      104,
                                      176,
                                    ),
                                    width: 240,
                                    fit: BoxFit.contain,
                                    excludeFromSemantics: true,
                                    cacheWidth: 640,
                                  ),
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      'Abashyaka',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .displaySmall
                                          ?.copyWith(
                                            fontSize: 48,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -1.6,
                                            color: AbashyakaTheme.darkGreen,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _OrangeStroke(width: 32),
                                      SizedBox(width: 12),
                                      Flexible(
                                        child: Text(
                                          'ଆବଶ୍ୟକ',
                                          locale: Locale('or'),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 27,
                                            color: AbashyakaTheme.darkGreen,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      _OrangeStroke(width: 32),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Everything You Need, Locally.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AbashyakaTheme.darkGreen,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FontStyle.italic,
                                      height: 1.4,
                                    ),
                                  ),
                                  const Align(
                                    alignment: Alignment.centerRight,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        top: 8,
                                        right: 24,
                                      ),
                                      child: _OrangeStroke(width: 120),
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  const Text(
                                    'ସବୁ ଆବଶ୍ୟକତା,\nଆପଣଙ୍କ ପାଖରେ।',
                                    locale: Locale('or'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 26,
                                      height: 1.5,
                                      fontWeight: FontWeight.w700,
                                      color: AbashyakaTheme.darkGreen,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: _OrangeStroke(width: 120),
                                  ),
                                  const SizedBox(height: 16),
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AbashyakaTheme.green,
                                      semanticsLabel: 'Restoring your session',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _OrangeStroke extends StatelessWidget {
  const _OrangeStroke({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: width,
      height: 5,
      child: CustomPaint(painter: _StrokePainter()),
    ),
  );
}

class _StrokePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = AbashyakaTheme.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(2, size.height - 1)
        ..quadraticBezierTo(size.width / 2, 0, size.width - 2, size.height - 1),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_StrokePainter oldDelegate) => false;
}
