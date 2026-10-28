import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Saved favourites screen.
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key});

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(favoritesProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Saved'),
        actions: [
          if (state.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _showClearDialog(),
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? _buildError(state.error!)
              : state.items.isEmpty
                  ? _buildEmpty()
                  : _buildList(state.items),
    );
  }

  Widget _buildError(String error) {
    final isAuthError = error.contains('401') || error.toLowerCase().contains('unauthorized');
    if (isAuthError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite_outline, size: 64, color: AppTheme.hintText),
              const SizedBox(height: 16),
              const Text(
                'Save your favorite places',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to sync your saved businesses and services across devices.',
                style: TextStyle(color: AppTheme.secondaryText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => ref.read(favoritesProvider.notifier).load(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 16),
            const Text(
              'Unable to load saved places',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.mainText),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please check your internet connection and try again.',
              style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.read(favoritesProvider.notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
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
    );
  }

  Widget _buildList(List<Business> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(kScreenPadding, 12, kScreenPadding, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final biz = items[index];
        return _SavedBusinessCard(
          business: biz,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BusinessDetailScreen(businessId: biz.id),
          )),
          onFavoriteToggle: () => ref.read(favoritesProvider.notifier).toggle(biz.id),
        );
      },
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all saved?'),
        content: const Text('This will remove all businesses from your saved list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref.read(favoritesProvider.notifier).clear();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _SavedBusinessCard extends StatelessWidget {
  final Business business;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const _SavedBusinessCard({
    required this.business,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      onTap: onTap,
      child: Row(
        children: [
          // Category icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_getCategoryIcon(business.categorySlug), color: AppTheme.primary, size: 28),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  business.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (business.distanceM != null) ...[
                      const Icon(Icons.location_on_outlined, size: 13, color: AppTheme.hintText),
                      const SizedBox(width: 4),
                      Text(
                        business.distanceText,
                        style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      business.categoryName ?? business.categorySlug,
                      style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Favorite button
          IconButton(
            icon: const Icon(Icons.favorite, color: AppTheme.error, size: 24),
            onPressed: onFavoriteToggle,
            tooltip: 'Remove from saved',
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'restaurant':
        return Icons.restaurant;
      case 'grocery':
        return Icons.store;
      case 'medical':
        return Icons.local_pharmacy;
      case 'salon':
        return Icons.face;
      case 'hardware':
        return Icons.build;
      default:
        return Icons.shop;
    }
  }
}