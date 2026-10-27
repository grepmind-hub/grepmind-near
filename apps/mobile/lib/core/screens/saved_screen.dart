import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Saved favourites screen.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Saved'),
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_outline, size: 64, color: AppTheme.hintText),
            SizedBox(height: 16),
            Text(
              'No saved businesses yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
            ),
            SizedBox(height: 8),
            Text(
              'Tap the heart on a business to save it here.',
              style: TextStyle(color: AppTheme.secondaryText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
