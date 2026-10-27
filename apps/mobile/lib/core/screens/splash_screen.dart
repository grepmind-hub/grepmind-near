import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Splash screen shown while the app initializes and session loads.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.onPrimary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.explore, color: AppTheme.primary, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Grepmind Near',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppTheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Everything nearby. One tap away.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.onPrimary.withValues(alpha: 0.9),
                  ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.onPrimary)),          ],
        ),
      ),
    );
  }
}
