import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Splash screen shown while the app initializes and session loads.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF2FF), AppTheme.background, Color(0xFFE7F5F3)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final illustrationHeight = (constraints.maxHeight * 0.48).clamp(
                240.0,
                380.0,
              );
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 20,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 40,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(17),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.18),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.near_me_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'GREPMIND NEAR',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: AppTheme.primary,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        SizedBox(
                          height: illustrationHeight,
                          child: Image.asset(
                            'assets/images/splash_discovery.png',
                            fit: BoxFit.contain,
                            semanticLabel:
                                'Nearby shops and services on a local map',
                          ),
                        ),
                        Text(
                          'Everything nearby.\nOne tap away.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                                color: AppTheme.mainText,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Find trusted local shops and services around you.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.secondaryText),
                        ),
                        const SizedBox(height: 28),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
