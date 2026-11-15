import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/platform_catalog_provider.dart';
import 'package:grepmind_mobile/core/providers/platform_cart_provider.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/platform_cart_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class PlatformProductDetailScreen extends ConsumerWidget {
  final String id;
  final String vertical;
  final String city;
  final String locality;
  final String localityId;

  const PlatformProductDetailScreen({
    super.key,
    required this.id,
    required this.vertical,
    required this.city,
    this.locality = '',
    this.localityId = '',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserProvider)?.id ?? '';
    final cartScope = PlatformCartScope(
      userId: userId,
      vertical: vertical,
      localityId: localityId,
      locality: locality,
      district: city,
    );
    final cart = ref.watch(platformCartProvider(cartScope));
    final query = PlatformCatalogQuery(
      vertical: vertical,
      city: city,
      locality: locality,
      localityId: localityId,
    );
    final product = ref.watch(
      platformCatalogProductProvider((id: id, query: query)),
    );
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text('Product details'),
      ),
      body: product.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 42,
                  color: AppTheme.secondaryText,
                ),
                const SizedBox(height: 12),
                Text(
                  'Product unavailable',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  platformCatalogErrorMessage(error),
                  textAlign: TextAlign.center,
                ),
                TextButton.icon(
                  onPressed: () => ref.invalidate(
                    platformCatalogProductProvider((id: id, query: query)),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (item) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 285,
                    child: item.imageUrls.isEmpty
                        ? const _DetailPlaceholder()
                        : PageView(
                            children: item.imageUrls
                                .map(
                                  (url) => CachedNetworkImage(
                                    imageUrl: apiClient.resolveMediaUrl(url),
                                    fit: BoxFit.cover,
                                    placeholder: (_, _) =>
                                        const _DetailPlaceholder(),
                                    errorWidget: (_, _, _) =>
                                        const _DetailPlaceholder(),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.categoryName.toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: AppTheme.secondary,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          item.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            item.description,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: AppTheme.secondaryText),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Text(
                          'Available options',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 9),
                        if (item.variants.isEmpty)
                          const Text('No options are currently available.')
                        else
                          for (final variant in item.variants)
                            Card(
                              color: AppTheme.surface,
                              child: ListTile(
                                title: Text(variant.name),
                                subtitle: Text(
                                  '${variant.unitLabel} · ₹${(variant.priceMinor / 100).toStringAsFixed(2)}',
                                ),
                                trailing: Text(
                                  cart.lines[variant.id] == null
                                      ? 'Add'
                                      : '${cart.lines[variant.id]!.quantity} in cart',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                onTap: userId.isEmpty || localityId.isEmpty
                                    ? null
                                    : () async {
                                        final added = await ref
                                            .read(
                                              platformCartProvider(cartScope)
                                                  .notifier,
                                            )
                                            .add(item, variant);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                added
                                                    ? '${item.name} added to ${vertical == 'food' ? 'Food' : 'Grocery'} cart.'
                                                    : 'This item cannot be added right now.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                              ),
                            ),
                        const SizedBox(height: 17),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: AppTheme.primary,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Grepmind verifies availability and final pricing before checkout. Choose sandbox UPI or eligible cash on delivery when you place your order.',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            key: const ValueKey('platform_open_cart'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.emerald,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFFE2E8F0),
                              disabledForegroundColor: const Color(0xFF94A3B8),
                              elevation: cart.isEmpty ? 0 : 2,
                              shadowColor: const Color(0x33059669),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed:
                                userId.isEmpty ||
                                    localityId.isEmpty ||
                                    cart.isEmpty
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PlatformCartScreen(scope: cartScope),
                                    ),
                                  ),
                            icon: const Icon(Icons.shopping_cart_outlined),
                            label: Text(
                              cart.isEmpty
                                  ? 'Add a product option above'
                                  : 'View cart · ${cart.itemCount} ${cart.itemCount == 1 ? 'item' : 'items'}',
                            ),
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
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    color: AppTheme.surfaceVariant,
    child: const Center(
      child: Icon(
        Icons.shopping_bag_outlined,
        size: 56,
        color: AppTheme.secondaryText,
      ),
    ),
  );
}
