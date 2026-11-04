import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/home_feed_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class HomeNewNearYouScreen extends StatefulWidget {
  const HomeNewNearYouScreen({super.key, required this.city});
  final String city;

  @override
  State<HomeNewNearYouScreen> createState() => _HomeNewNearYouScreenState();
}

class _HomeNewNearYouScreenState extends State<HomeNewNearYouScreen> {
  String _filter = 'all';
  final List<HomeCatalogItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _items.clear();
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final offset = reset ? 0 : _items.length;
    try {
      final response = await apiClient.get(
        '/catalog/new-arrivals',
        queryParameters: {
          'city': widget.city,
          'type': _filter,
          'limit': _pageSize,
          'offset': offset,
        },
      );
      final body = response.data as Map<String, dynamic>;
      final rows = (body['data'] as List<dynamic>? ?? const [])
          .map((row) => HomeCatalogItem.fromJson(row as Map<String, dynamic>))
          .toList(growable: false);
      final meta = body['meta'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = meta?['has_more'] as bool? ?? false;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'We couldn’t load new items. Check your connection and retry.';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text('New near you'),
      backgroundColor: AppTheme.background,
      surfaceTintColor: Colors.transparent,
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            'Recently published in ${widget.city}',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppTheme.secondaryText),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            children: [
              _filterChip('all', 'All'),
              const SizedBox(width: 8),
              _filterChip('products', 'Products'),
              const SizedBox(width: 8),
              _filterChip('services', 'Services'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _items.isEmpty
              ? _message(
                  Icons.wifi_off_rounded,
                  _error!,
                  action: TextButton(
                    onPressed: () => _load(reset: true),
                    child: const Text('Retry'),
                  ),
                )
              : _items.isEmpty
              ? _message(
                  Icons.auto_awesome_outlined,
                  'Nothing new here yet',
                  subtitle: 'Newly published products and active services will appear when local businesses add them.',
                )
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.extentAfter < 320 &&
                          _hasMore &&
                          !_loadingMore) {
                        _load(reset: false);
                      }
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index == _items.length)
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        final item = _items[index];
                        return _CatalogArrivalTile(
                          item: item,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BusinessDetailScreen(
                                businessId: item.businessId,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _filterChip(String value, String label) => ChoiceChip(
    label: Text(label),
    selected: _filter == value,
    onSelected: (_) => _setFilter(value),
    showCheckmark: false,
    selectedColor: AppTheme.primary,
    labelStyle: TextStyle(
      color: _filter == value ? Colors.white : AppTheme.mainText,
      fontWeight: FontWeight.w700,
    ),
    shape: const StadiumBorder(side: BorderSide(color: AppTheme.border)),
  );

  Widget _message(
    IconData icon,
    String title, {
    String? subtitle,
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppTheme.secondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
          ],
          if (action != null) action,
        ],
      ),
    ),
  );
}

class _CatalogArrivalTile extends StatelessWidget {
  const _CatalogArrivalTile({required this.item, required this.onTap});
  final HomeCatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = item.imageUrl == null || item.imageUrl!.isEmpty
        ? null
        : apiClient.resolveMediaUrl(item.imageUrl!);
    final price = item.price == null
        ? null
        : item.priceMax == null || item.priceMax == item.price
        ? '₹${item.price!.toStringAsFixed(0)}'
        : '₹${item.price!.toStringAsFixed(0)} – ₹${item.priceMax!.toStringAsFixed(0)}';
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 94,
                  height: 94,
                  child: image == null
                      ? const _ArrivalPlaceholder()
                      : Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const _ArrivalPlaceholder(),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.type == 'product' ? 'PRODUCT' : 'SERVICE',
                      style: const TextStyle(
                        color: AppTheme.secondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .7,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.categoryName} · ${item.locality?.isNotEmpty == true ? item.locality : item.city}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppTheme.secondaryText),
                    ),
                    if (price != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        price,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrivalPlaceholder extends StatelessWidget {
  const _ArrivalPlaceholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppTheme.surfaceVariant,
    child: Center(
      child: Icon(
        Icons.storefront_outlined,
        color: AppTheme.secondary,
        size: 30,
      ),
    ),
  );
}
