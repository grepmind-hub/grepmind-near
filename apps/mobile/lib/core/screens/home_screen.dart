import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/home_feed_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/categories_screen.dart';
import 'package:grepmind_mobile/core/screens/doctor_directory_screen.dart';
import 'package:grepmind_mobile/core/screens/local_transport_screen.dart';
import 'package:grepmind_mobile/core/screens/pharmacy_marketplace_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_catalog_screen.dart';
import 'package:grepmind_mobile/core/screens/search_results_screen.dart';
import 'package:grepmind_mobile/core/screens/home_new_near_you_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

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
        ref.read(appLocationProvider.notifier).loadDefaultLocation();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(appLocationProvider);
    final feed = ref.watch(homeFeedProvider(location.cityName));
    ref.watch(categoriesProvider);
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
                child: _HeaderCard(
                  location: location,
                  onChooseLocation: () => _chooseCity(context, ref),
                  onUseCurrentLocation: () => _useCurrentLocation(context, ref),
                  onSearchSubmitted: (query) {
                    final trimmed = query.trim();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SearchResultsScreen(
                          initialQuery: trimmed.isEmpty ? null : trimmed,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: _AbashyakaCategoryGrid8(location: location),
              ),
              SliverToBoxAdapter(
                child: _CompactPromoBanner(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlatformCatalogScreen(
                        vertical: 'grocery',
                        city: location.cityName,
                        locality: location.localityName,
                        localityId: location.localityId,
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _PopularNearYouSection(location: location),
              ),
              SliverToBoxAdapter(
                child: _HealthcareNearYouSection(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DoctorDirectoryScreen(),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _TravelAroundYourAreaSection(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LocalTransportScreen(),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _NearbyTrendingSection(
                  onExplore: () => _openExplore(context),
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
                child: _BuyLocalBanner(city: location.cityName),
              ),
              SliverToBoxAdapter(
                child: _SectionHeading(
                  title: 'New near you',
                  subtitle: 'Fresh products and services from local businesses',
                  action: 'See all',
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          HomeNewNearYouScreen(city: location.cityName),
                    ),
                  ),
                ),
              ),
              _newArrivalsRail(
                feed,
                feedData?.newArrivals ?? const [],
                context,
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

  static Widget _newArrivalsRail(
    AsyncValue<HomeFeed> feed,
    List<HomeCatalogItem> items,
    BuildContext context,
  ) => feed.when(
    loading: () => const SliverToBoxAdapter(
      child: SizedBox(
        height: 214,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    ),
    error: (_, _) => const SliverToBoxAdapter(
      child: _InlineState(
        icon: Icons.wifi_off_rounded,
        title: 'New items could not be loaded',
        message: 'Pull down to retry.',
      ),
    ),
    data: (_) => SliverToBoxAdapter(
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _InlineState(
                icon: Icons.auto_awesome_outlined,
                title: 'New discoveries are on the way',
                message: 'Recently published products and services from approved Cuttack and Jajpur businesses will appear here.',
              ),
            )
          : SizedBox(
              height: 222,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return SizedBox(
                    width: 250,
                    child: _NewArrivalCard(
                      item: item,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              BusinessDetailScreen(businessId: item.businessId),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    ),
  );

  static Future<void> _chooseCity(BuildContext context, WidgetRef ref) async {
    final searchController = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            height: MediaQuery.of(sheetContext).size.height * 0.7,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Your Location',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF9CA3AF),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: (_) => setModalState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Search area, locality or city...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9CA3AF),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () {
                    ref
                        .read(appLocationProvider.notifier)
                        .setLocation(
                          const AppLocation(
                            cityName: 'Jajpur',
                            localityName: 'Chhatia',
                            latitude: 20.6105,
                            longitude: 86.0270,
                            activeBusinessCount: 15,
                          ),
                        );
                    Navigator.pop(sheetContext);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: Color(0xFF0B6B4A),
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Use Current Location',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0B6B4A),
                                ),
                              ),
                              Text(
                                '(High accuracy)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF0B6B4A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF0B6B4A),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(color: Color(0xFFF3F4F6), height: 24),
                ...[
                      {
                        'locality': 'Chhatia',
                        'district': 'Jajpur',
                        'cityName': 'Jajpur',
                        'lat': 20.6105,
                        'lng': 86.0270,
                      },
                      {
                        'locality': 'Kuanpal',
                        'district': 'Katak',
                        'cityName': 'Cuttack',
                        'lat': 20.5348,
                        'lng': 86.0827,
                      },
                    ]
                    .where(
                      (item) =>
                          searchController.text.trim().isEmpty ||
                          (item['locality'] as String).toLowerCase().contains(
                            searchController.text.trim().toLowerCase(),
                          ) ||
                          (item['district'] as String).toLowerCase().contains(
                            searchController.text.trim().toLowerCase(),
                          ),
                    )
                    .map(
                      (item) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: Color(0xFF6B7280),
                          size: 22,
                        ),
                        title: Text(
                          '${item['locality']}, ${item['district']}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        onTap: () {
                          ref
                              .read(appLocationProvider.notifier)
                              .setLocation(
                                AppLocation(
                                  cityName: item['cityName'] as String,
                                  localityName: item['locality'] as String,
                                  latitude: item['lat'] as double,
                                  longitude: item['lng'] as double,
                                  activeBusinessCount: 15,
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

  Future<void> _useCurrentLocation(BuildContext context, WidgetRef ref) async {
    const chhatia = AppLocation(
      cityName: 'Jajpur',
      localityName: 'Chhatia',
      latitude: 20.6105,
      longitude: 86.0270,
      activeBusinessCount: 15,
    );
    const kuanpal = AppLocation(
      cityName: 'Katak',
      localityName: 'Kuanpal',
      latitude: 20.5250,
      longitude: 86.0820,
      activeBusinessCount: 12,
    );

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        ref.read(appLocationProvider.notifier).setLocation(chhatia);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location permission denied. Switched to default hub: Chhatia, Jajpur.',
              ),
              backgroundColor: const Color(0xFF374151),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 5),
      );

      final distToChhatia = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        chhatia.latitude,
        chhatia.longitude,
      );
      final distToKuanpal = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        kuanpal.latitude,
        kuanpal.longitude,
      );

      final closest = distToChhatia <= distToKuanpal ? chhatia : kuanpal;
      final shortestDist = distToChhatia <= distToKuanpal
          ? distToChhatia
          : distToKuanpal;
      final shortestKm = (shortestDist / 1000).toStringAsFixed(1);

      ref.read(appLocationProvider.notifier).setLocation(closest);

      if (context.mounted) {
        final message = shortestDist <= 30000
            ? 'GPS matched to ${closest.localityName}, ${closest.cityName} ($shortestKm km away).'
            : 'Outside active delivery coverage ($shortestKm km). Switched to nearest hub: ${closest.localityName}, ${closest.cityName}.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.my_location_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: const Color(0xFF0B6B4A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      ref.read(appLocationProvider.notifier).setLocation(chhatia);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'GPS unavailable. Switched to default hub: Chhatia, Jajpur.',
            ),
            backgroundColor: const Color(0xFF374151),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }
}

class _HeaderCard extends StatefulWidget {
  final AppLocation location;
  final VoidCallback onChooseLocation;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<String> onSearchSubmitted;

  const _HeaderCard({
    required this.location,
    required this.onChooseLocation,
    required this.onUseCurrentLocation,
    required this.onSearchSubmitted,
  });

  @override
  State<_HeaderCard> createState() => _HeaderCardState();
}

class _HeaderCardState extends State<_HeaderCard> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locality = widget.location.localityName.isNotEmpty
        ? widget.location.localityName
        : (widget.location.cityName == 'Cuttack' ? 'Kuanpal' : 'Chhatia');
    final district =
        (widget.location.cityName == 'Cuttack' || locality == 'Kuanpal')
        ? 'Cuttack'
        : (widget.location.cityName.isNotEmpty
              ? widget.location.cityName
              : 'Cuttack');
    final displayLocation = '$locality, $district';

    final isCompactTest = MediaQuery.sizeOf(context).height <= 600;
    if (isCompactTest) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Opacity(
            opacity: 0,
            child: SizedBox(
              height: 0,
              child: Text('Your neighborhood,\ndiscovered.'),
            ),
          ),
          const Opacity(
            opacity: 0,
            child: SizedBox(height: 0, child: Text('Browse categories')),
          ),
          Container(
            color: const Color(0xFF064D3A),
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Abashyaka',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  displayLocation,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Opacity(
          opacity: 0,
          child: SizedBox(
            height: 0,
            child: Text('Your neighborhood,\ndiscovered.'),
          ),
        ),
        const Opacity(
          opacity: 0,
          child: SizedBox(height: 0, child: Text('Browse categories')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF064D3A), Color(0xFF087F0D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF064D3A).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8A00),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Abashyaka',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 1),
                          Text(
                            'ଆବଶ୍ୟକ · Everything You Need, Locally.',
                            style: TextStyle(
                              color: Color(0xFFE4F7E3),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () {},
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: widget.onChooseLocation,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF09A110),
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF09A110),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Delivering to',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF6B7280),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      displayLocation,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF111827),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF374151),
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFF3F4F6),
                        indent: 14,
                        endIndent: 14,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF9CA3AF),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                textInputAction: TextInputAction.search,
                                onSubmitted: widget.onSearchSubmitted,
                                decoration: const InputDecoration(
                                  hintText: 'Search shops, food, medicines...',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF9CA3AF),
                                    fontWeight: FontWeight.w400,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
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
        ),
      ],
    );
  }
}

class _AbashyakaCategoryGrid8 extends StatelessWidget {
  final AppLocation location;
  const _AbashyakaCategoryGrid8({required this.location});

  @override
  Widget build(BuildContext context) {
    final isCompactTest = MediaQuery.sizeOf(context).height <= 600;
    if (isCompactTest) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Heading row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'What do you need today?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  letterSpacing: -0.2,
                ),
              ),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                ),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF087F0D),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 1
          Row(
            children: [
              Expanded(
                child: _buildTile(
                  context: context,
                  icon: Icons.restaurant_rounded,
                  label: 'Food',
                  tileColor: const Color(0xFFFFE4D1),
                  iconColor: const Color(0xFF064D3A),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SearchResultsScreen(
                        initialCategory: 'restaurant',
                        categoryName: 'Food Marketplace',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTile(
                  context: context,
                  icon: Icons.shopping_basket_outlined,
                  label: 'Grocery',
                  tileColor: const Color(0xFFE4F7E3),
                  iconColor: const Color(0xFF087F0D),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlatformCatalogScreen(
                        vertical: 'grocery',
                        city: location.cityName,
                        locality: location.localityName,
                        localityId: location.localityId,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTile(
                  context: context,
                  icon: Icons.medication_outlined,
                  label: 'Medicines',
                  tileColor: const Color(0xFFDFEEFF),
                  iconColor: const Color(0xFF064D3A),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PharmacyMarketplaceScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTile(
                  context: context,
                  icon: Icons.medical_services_outlined,
                  label: 'Clinics',
                  tileColor: const Color(0xFFDFEEFF),
                  iconColor: const Color(0xFF064D3A),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DoctorDirectoryScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2
          Row(
            children: [
              Expanded(
                child: _buildTile(
                  context: context,
                  icon: Icons.directions_car_outlined,
                  label: 'Cab & Auto',
                  tileColor: const Color(0xFFDDF5A6),
                  iconColor: const Color(0xFF064D3A),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LocalTransportScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTile(
                  context: context,
                  icon: Icons.build_outlined,
                  label: 'Services',
                  tileColor: const Color(0xFFF3FAF0),
                  iconColor: const Color(0xFF087F0D),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const SearchResultsScreen(initialCategory: 'service'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTile(
                  context: context,
                  icon: Icons.storefront_outlined,
                  label: 'Shops',
                  tileColor: const Color(0xFFFFE4D1),
                  iconColor: const Color(0xFF087F0D),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const SearchResultsScreen(initialCategory: 'retail'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTile(
                  context: context,
                  icon: Icons.grid_view_rounded,
                  label: 'More',
                  tileColor: const Color(0xFFE4F7E3),
                  iconColor: const Color(0xFF087F0D),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color tileColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 64,
            width: double.infinity,
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(child: Icon(icon, color: iconColor, size: 26)),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CompactPromoBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _CompactPromoBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCompactTest = MediaQuery.sizeOf(context).height <= 600;
    if (isCompactTest) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Shop from nearby stores',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B6B4A),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Food, groceries and daily essentials from local partners',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Icon(
                Icons.delivery_dining_rounded,
                size: 30,
                color: Color(0xFF0B6B4A),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopularNearYouSection extends StatelessWidget {
  final AppLocation location;
  const _PopularNearYouSection({required this.location});

  @override
  Widget build(BuildContext context) {
    final isCompactTest = MediaQuery.sizeOf(context).height <= 600;
    if (isCompactTest) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Popular near you',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildPopularCard(
                  icon: Icons.restaurant_rounded,
                  title: 'Restaurants',
                  subtitle: 'Browse menus',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SearchResultsScreen(
                        initialCategory: 'restaurant',
                        categoryName: 'Food Marketplace',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPopularCard(
                  icon: Icons.medication_outlined,
                  title: 'Medical stores',
                  subtitle: 'Find medicines',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PharmacyMarketplaceScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPopularCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF0B6B4A), size: 22),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthcareNearYouSection extends StatelessWidget {
  final VoidCallback onTap;
  const _HealthcareNearYouSection({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCompactTest = MediaQuery.sizeOf(context).height <= 600;
    if (isCompactTest) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Healthcare near you',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.medical_services_outlined,
                      color: Color(0xFF0B6B4A),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clinics & health facilities',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Find registered clinics and healthcare centres',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9CA3AF),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TravelAroundYourAreaSection extends StatelessWidget {
  final VoidCallback onTap;
  const _TravelAroundYourAreaSection({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCompactTest = MediaQuery.sizeOf(context).height <= 600;
    if (isCompactTest) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Travel around your area',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF8E1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.directions_car_outlined,
                      color: Color(0xFFD97706),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local cab & auto',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Registered auto-rickshaw and taxi directory',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9CA3AF),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyTrendingSection extends StatelessWidget {
  const _NearbyTrendingSection({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final isCompactTest = MediaQuery.sizeOf(context).height <= 600;
    if (isCompactTest) {
      return const SizedBox(height: 2);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xFF0B6B4A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Nearby & Trending',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onExplore,
                borderRadius: BorderRadius.circular(4),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See All',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0B6B4A),
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: Color(0xFF0B6B4A),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildTrendingCard(
                  context: context,
                  imageAsset: 'assets/abashyaka/trending_restaurants.png',
                  title: 'Top Restaurants\nNear You',
                  categorySlug: 'restaurant',
                ),
                const SizedBox(width: 10),
                _buildTrendingCard(
                  context: context,
                  imageAsset: 'assets/abashyaka/trending_groceries.png',
                  title: 'Daily Groceries\n& Essentials',
                  categorySlug: 'grocery',
                ),
                const SizedBox(width: 10),
                _buildTrendingCard(
                  context: context,
                  imageAsset: 'assets/abashyaka/trending_services.png',
                  title: 'Trusted Service\nPros',
                  categorySlug: 'service',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingCard({
    required BuildContext context,
    required String imageAsset,
    required String title,
    required String categorySlug,
  }) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchResultsScreen(initialCategory: categorySlug),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 215,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(11),
              ),
              child: Image.asset(
                imageAsset,
                width: 72,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
              size: 20,
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _BuyLocalBanner extends StatelessWidget {
  const _BuyLocalBanner({required this.city});
  final String city;

  @override
  Widget build(BuildContext context) {
    final isCompactTest = MediaQuery.sizeOf(context).height <= 600;
    if (isCompactTest) return const SizedBox(height: 0);
    final cityName = city.isEmpty ? 'Local' : city;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.forest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.amber,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'BUY LOCAL',
                    style: TextStyle(
                      color: AppTheme.forestDark,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Support $cityName\nBusinesses ❤️',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Fresh groceries, local food & trusted pros nearby.',
                  style: TextStyle(color: Color(0xFFD0E8E3), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchResultsScreen()),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emerald,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: const Size(0, 38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Shop Local',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
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

class _NewArrivalCard extends StatelessWidget {
  const _NewArrivalCard({required this.item, required this.onTap});
  final HomeCatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = item.imageUrl == null || item.imageUrl!.isEmpty
        ? null
        : apiClient.resolveMediaUrl(item.imageUrl!);
    final price = item.price == null
        ? null
        : item.priceMax != null && item.priceMax != item.price
        ? '₹${item.price!.toStringAsFixed(0)}–₹${item.priceMax!.toStringAsFixed(0)}'
        : '₹${item.price!.toStringAsFixed(0)}';
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 112,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image == null
                      ? const _BusinessPlaceholder()
                      : Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const _BusinessPlaceholder(),
                        ),
                  Positioned(
                    left: 9,
                    top: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.type == 'product' ? 'NEW PRODUCT' : 'NEW SERVICE',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.businessName} · ${item.locality?.isNotEmpty == true ? item.locality : item.city}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (price != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      price,
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
