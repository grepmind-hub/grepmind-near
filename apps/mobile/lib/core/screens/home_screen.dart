import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/home_feed_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/categories_screen.dart';
import 'package:grepmind_mobile/core/screens/search_results_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/utils/category_sample_image.dart';

/// Customer Home is a live local feed: current offers, categories and approved
/// businesses are loaded from the API for the selected supported city.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(
          homeFeedProvider(ref.read(appLocationProvider).cityName),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(appLocationProvider);
    final feed = ref.watch(homeFeedProvider(location.cityName));
    final categories = ref.watch(categoriesProvider);
    final feedData = feed.valueOrNull;
    final offerBusinessIds =
        feedData?.offers.map((offer) => offer.businessId).toSet() ?? <String>{};
    final openBusinesses = (feedData?.openNow ?? const <Business>[])
        .where((business) => !offerBusinessIds.contains(business.id))
        .toList(growable: false);
    final usedBusinessIds = {
      ...offerBusinessIds,
      ...openBusinesses.map((item) => item.id),
    };
    final serviceBusinesses = (feedData?.services ?? const <Business>[])
        .where((business) => !usedBusinessIds.contains(business.id))
        .toList(growable: false);
    usedBusinessIds.addAll(serviceBusinesses.map((item) => item.id));
    final recentBusinesses = (feedData?.recentlyAdded ?? const <Business>[])
        .where((business) => !usedBusinessIds.contains(business.id))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.refresh(homeFeedProvider(location.cityName).future),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  location: location,
                  onChoose: () => _chooseCity(context, ref),
                ),
              ),
              SliverToBoxAdapter(
                child: _WelcomePanel(
                  city: location.cityName,
                  onExplore: () => _openExplore(context),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionHeading(
                  title: 'Browse categories',
                  action: 'All categories',
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 104,
                  child: categories.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : categories.error != null
                      ? const Center(
                          child: Text(
                            'Categories are temporarily unavailable.',
                          ),
                        )
                      : categories.items.isEmpty
                      ? const Center(
                          child: Text('No categories are available yet.'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.items.take(12).length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final category = categories.items[index];
                            return _CategoryTile(
                              name: category.name,
                              icon: CategoriesScreen.getCategoryIcon(
                                category.slug,
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SearchResultsScreen(
                                    initialCategory: category.slug,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionHeading(
                  title: 'Live offers',
                  subtitle:
                      'Available now in ${location.cityName.isEmpty ? 'your selected city' : location.cityName}',
                ),
              ),
              SliverToBoxAdapter(
                child: feed.when(
                  loading: () => const SizedBox(
                    height: 154,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (_, _) => _InlineState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Offers could not be loaded',
                    message: 'Pull down to try again.',
                    action: TextButton(
                      onPressed: () =>
                          ref.invalidate(homeFeedProvider(location.cityName)),
                      child: const Text('Retry'),
                    ),
                  ),
                  data: (data) => data.offers.isEmpty
                      ? const _InlineState(
                          icon: Icons.local_offer_outlined,
                          title: 'No live offers right now',
                          message: 'Approved offers from local businesses will appear here while they are active.',
                        )
                      : SizedBox(
                          height: 154,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            scrollDirection: Axis.horizontal,
                            itemCount: data.offers.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) => _OfferCard(
                              offer: data.offers[index],
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BusinessDetailScreen(
                                    businessId: data.offers[index].businessId,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionHeading(
                  title: 'Open now',
                  action: 'See all',
                  onAction: () => _openExplore(context),
                ),
              ),
              _businessRail(
                feed,
                'No approved businesses are open right now.',
                openBusinesses,
                style: _RailStyle.open,
              ),
              SliverToBoxAdapter(
                child: _SectionHeading(
                  title: 'Services near you',
                  subtitle: 'Professionals currently accepting requests',
                  action: 'Find a service',
                  onAction: () => _openExplore(context),
                ),
              ),
              _businessRail(
                feed,
                'No service professionals are accepting requests in this city yet.',
                serviceBusinesses,
                style: _RailStyle.service,
              ),
              SliverToBoxAdapter(
                child: _SectionHeading(
                  title: 'Recently added',
                  subtitle: 'Newly approved local businesses',
                  action: 'Explore',
                  onAction: () => _openExplore(context),
                ),
              ),
              _recentBusinessRail(feed, recentBusinesses),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );
  }

  static void _openExplore(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SearchResultsScreen()),
  );

  static Widget _businessRail(
    AsyncValue<HomeFeed> feed,
    String emptyMessage,
    List<Business> items, {
    required _RailStyle style,
  }) => feed.when(
    loading: () => const SliverToBoxAdapter(
      child: SizedBox(
        height: 138,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    ),
    error: (_, _) => const SliverToBoxAdapter(
      child: _InlineState(
        icon: Icons.wifi_off_rounded,
        title: 'Businesses could not be loaded',
        message: 'Pull down to retry.',
      ),
    ),
    data: (_) => SliverToBoxAdapter(
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Text(
                emptyMessage,
                style: const TextStyle(color: AppTheme.secondaryText),
              ),
            )
          : SizedBox(
              height: style == _RailStyle.service ? 132 : 112,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) => SizedBox(
                  width: style == _RailStyle.service ? 300 : 320,
                  child: _BusinessTile(
                    business: items[index],
                    serviceStyle: style == _RailStyle.service,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BusinessDetailScreen(businessId: items[index].id),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );

  static Widget _recentBusinessRail(
    AsyncValue<HomeFeed> feed,
    List<Business> items,
  ) => feed.when(
    loading: () => const SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    ),
    error: (_, _) => const SliverToBoxAdapter(
      child: _InlineState(
        icon: Icons.wifi_off_rounded,
        title: 'Recent listings could not be loaded',
        message: 'Pull down to retry.',
      ),
    ),
    data: (_) => SliverToBoxAdapter(
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(
                'New approved businesses will appear here.',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
            )
          : SizedBox(
              height: 188,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => SizedBox(
                  width: 206,
                  child: _RecentBusinessCard(
                    business: items[index],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BusinessDetailScreen(businessId: items[index].id),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );

  static Future<void> _chooseCity(BuildContext context, WidgetRef ref) async {
    try {
      final response = await apiClient.get('/locations');
      final items = (response.data['data'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((item) => const {'Cuttack', 'Jajpur'}.contains(item['city']))
          .toList(growable: false);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose your city',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Discovery is currently available in Cuttack and Jajpur.',
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'City information is unavailable. Please try again later.',
                    ),
                  ),
                ...items.map(
                  (item) => ListTile(
                    leading: const Icon(
                      Icons.location_city_rounded,
                      color: AppTheme.primary,
                    ),
                    title: Text(item['city'] as String? ?? ''),
                    subtitle: Text('${item['count'] ?? 0} approved listings'),
                    onTap: () {
                      ref
                          .read(appLocationProvider.notifier)
                          .setLocation(
                            AppLocation(
                              cityName: item['city'] as String,
                              latitude: (item['latitude'] as num).toDouble(),
                              longitude: (item['longitude'] as num).toDouble(),
                              activeBusinessCount:
                                  (item['count'] as num?)?.toInt() ?? 0,
                            ),
                          );
                      Navigator.pop(sheetContext);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load supported cities. Please retry.'),
          ),
        );
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.location, required this.onChoose});
  final AppLocation location;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GREPMIND NEAR',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              InkWell(
                onTap: onChoose,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: AppTheme.secondary,
                        size: 19,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          location.cityName.isEmpty
                              ? 'Choose your city'
                              : location.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppTheme.secondaryText,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Search businesses',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchResultsScreen()),
          ),
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    ),
  );
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.city, required this.onExplore});
  final String city;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    height: 226,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/login_welcome.jpg', fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xE6F0F4FA), Color(0xA6F0F4FA), Color(0x22F0F4FA)],
              stops: [0, .55, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                'Your neighborhood,\ndiscovered.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 24,
                  height: 1.13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF14274D),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                city.isEmpty
                    ? 'Find trusted shops and services close to you.'
                    : 'Find trusted shops and services around $city.',
                style: const TextStyle(color: Color(0xFF34445F), height: 1.35),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onExplore,
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('Explore nearby'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
  });
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.name,
    required this.icon,
    required this.onTap,
  });
  final String name;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CategorySampleImage(index: categorySampleIndex('', name)),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: AppTheme.secondary, size: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppTheme.mainText),
          ),
        ],
      ),
    ),
  );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onTap});
  final HomeOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = (offer.imageUrl?.isNotEmpty ?? false)
        ? offer.imageUrl
        : offer.businessPhotoUrl;
    return SizedBox(
      width: 344,
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.white),
              Align(
                alignment: Alignment.centerLeft,
                child: ClipPath(
                  clipper: const _OfferImageClipper(),
                  child: SizedBox(
                    width: 164,
                    height: double.infinity,
                    child: image != null && image.isNotEmpty
                        ? Image.network(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const _OfferPlaceholder(),
                          )
                        : const _OfferPlaceholder(),
                  ),
                ),
              ),
              Padding(
              padding: const EdgeInsets.fromLTRB(170, 15, 10, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'LIVE OFFER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      offer.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${offer.businessName} · ${offer.locality ?? offer.city}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (offer.discountPercent != null) ...[
                      const SizedBox(height: 7),
                      Text(
                        '${offer.discountPercent}% OFF',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferImageClipper extends CustomClipper<Path> {
  const _OfferImageClipper();
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width - 24, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_OfferImageClipper oldClipper) => false;
}

class _OfferPlaceholder extends StatelessWidget {
  const _OfferPlaceholder();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFFE5EDFF), Color(0xFFE5F4F1)]),
    ),
    child: Center(
      child: Icon(
        Icons.local_offer_outlined,
        color: AppTheme.primary,
        size: 42,
      ),
    ),
  );
}

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({
    required this.business,
    required this.onTap,
    this.serviceStyle = false,
  });
  final Business business;
  final VoidCallback onTap;
  final bool serviceStyle;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.surface,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: serviceStyle ? 88 : 66,
                height: serviceStyle ? 82 : 66,
                child: business.coverPhotoUrl?.isNotEmpty == true
                    ? Image.network(
                        business.coverPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _BusinessPlaceholder(),
                      )
                    : const _BusinessPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${business.categoryName ?? business.categorySlug} · ${business.locality ?? business.city ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        serviceStyle || business.isOpenNow
                            ? Icons.circle
                            : Icons.schedule_rounded,
                        size: 11,
                        color: serviceStyle || business.isOpenNow
                            ? AppTheme.success
                            : AppTheme.secondaryText,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        serviceStyle ? 'Accepting requests' : 'Open now',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: AppTheme.secondaryText),
                      ),
                      if (business.distanceText.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.near_me_outlined,
                          size: 12,
                          color: AppTheme.secondaryText,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          business.distanceText,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
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

enum _RailStyle { open, service }

class _RecentBusinessCard extends StatelessWidget {
  const _RecentBusinessCard({required this.business, required this.onTap});
  final Business business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.surface,
    borderRadius: BorderRadius.circular(17),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                business.coverPhotoUrl?.isNotEmpty == true
                    ? Image.network(
                        business.coverPhotoUrl!,
                        fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _BusinessPlaceholder(),
                      )
                : const _BusinessPlaceholder(),
                Positioned(
                  right: 8,
                  top: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      child: Text(
                        'NEW',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  business.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${business.categoryName ?? business.categorySlug} · ${business.city ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _BusinessPlaceholder extends StatelessWidget {
  const _BusinessPlaceholder();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: AppTheme.surfaceVariant),
    child: Center(
      child: Icon(
        Icons.storefront_outlined,
        color: AppTheme.secondary,
        size: 26,
      ),
    ),
  );
}

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 18),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.primaryContainer,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
              if (action != null)
                Align(alignment: Alignment.centerLeft, child: action!),
            ],
          ),
        ),
      ],
    ),
  );
}
