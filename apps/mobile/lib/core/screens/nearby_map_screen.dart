import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/service_pro_screen.dart';
import 'package:grepmind_mobile/core/screens/categories_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen 10: Nearby Interactive Map.
///
/// Features:
/// - Interactive map markers with custom category hues
/// - Top floating Category Filter Carousel (All, Electrician, Hardware, etc.)
/// - Floating Bottom Business Preview Card matching ref-image/Nearby map.png
/// - Dynamic fallback Radar Map Canvas with concentric distance rings & interactive pins
/// - Quick actions: GPS center me, directions launcher, profile routing
class NearbyMapScreen extends ConsumerStatefulWidget {
  const NearbyMapScreen({
    super.key,
    this.useDeviceLocation = true,
    this.initialRadarView = false,
  });
  final bool useDeviceLocation;
  final bool initialRadarView;

  @override
  ConsumerState<NearbyMapScreen> createState() => _NearbyMapScreenState();
}

class _NearbyMapScreenState extends ConsumerState<NearbyMapScreen>
    with SingleTickerProviderStateMixin {
  final Completer<GoogleMapController> _mapController = Completer();
  GoogleMapController? _mapControllerInstance;
  CameraPosition? _currentPosition;
  Set<Marker> _markers = {};
  bool _isLoading = false;
  String? _error;
  int _loadSequence = 0;
  bool _hasGpsFix = false;
  StreamSubscription<Position>? _positionStream;

  // Selected Category filter
  String _selectedCategorySlug = 'all';

  // Selected Business for bottom floating preview card
  Business? _selectedBusiness;

  // Fallback radar view toggle
  bool _useRadarView = false;
  late AnimationController _radarAnimController;

  @override
  void initState() {
    super.initState();
    _useRadarView = widget.initialRadarView;
    _radarAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    if (widget.useDeviceLocation) {
      _requestLocationPermission();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _useDefaultLocation();
      });
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _radarAnimController.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _useDefaultLocation();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _useDefaultLocation();
        return;
      }
      _startLocationUpdates();
    } catch (_) {
      _useDefaultLocation();
    }
  }

  void _useDefaultLocation() {
    final location = ref.read(appLocationProvider);
    if (!const [
      'cuttack',
      'jajpur',
    ].contains(location.cityName.toLowerCase())) {
      if (mounted)
        setState(() {
          _error =
              'Choose Cuttack or Jajpur in Explore to browse listed shops.';
          _isLoading = false;
        });
      return;
    }
    final defLat = location.latitude;
    final defLng = location.longitude;
    _updateMapPosition(defLat, defLng);
    _loadNearbyBusinesses(defLat, defLng);
  }

  void _startLocationUpdates() {
    _isLoading = true;
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 100,
          ),
        ).listen(
          (Position position) {
            _hasGpsFix = true;
            _updateMapPosition(position.latitude, position.longitude);
            _loadNearbyBusinesses(position.latitude, position.longitude);
          },
          onError: (_) {
            _useDefaultLocation();
          },
        );
  }

  void _updateMapPosition(double lat, double lng) {
    final newPosition = CameraPosition(target: LatLng(lat, lng), zoom: 15.0);
    _currentPosition = newPosition;
    _mapControllerInstance?.animateCamera(
      CameraUpdate.newCameraPosition(newPosition),
    );
    if (mounted) setState(() {});
  }

  Future<void> _loadNearbyBusinesses(double lat, double lng) async {
    final sequence = ++_loadSequence;
    final city = ref.read(appLocationProvider).cityName;
    if (!const ['cuttack', 'jajpur'].contains(city.toLowerCase())) {
      if (mounted)
        setState(() {
          _error = 'Select Cuttack or Jajpur in Explore.';
          _isLoading = false;
        });
      return;
    }
    if (mounted)
      setState(() {
        _isLoading = true;
        _error = null;
      });
    try {
      final businessesState = ref.read(mapBusinessesProvider.notifier);
      await businessesState.nearby(
        lat: lat,
        lng: lng,
        city: city,
        categorySlug: _selectedCategorySlug == 'all'
            ? null
            : _selectedCategorySlug,
      );
      if (!mounted || sequence != _loadSequence) return;
      if (ref.read(mapBusinessesProvider).error != null)
        throw StateError('Nearby lookup failed');

      // Automatically select closest business if none selected
      final businesses = _filteredBusinesses;
      setState(
        () => _selectedBusiness = businesses.isEmpty ? null : businesses.first,
      );
      _updateMarkers();
    } catch (e) {
      if (mounted && sequence == _loadSequence)
        setState(() {
          _error = 'Unable to load nearby shops. Please try again.';
          _selectedBusiness = null;
          _markers = {};
        });
    } finally {
      if (mounted && sequence == _loadSequence)
        setState(() => _isLoading = false);
    }
  }

  List<Business> get _filteredBusinesses {
    final city = ref.read(appLocationProvider).cityName.toLowerCase();
    final list = ref
        .read(mapBusinessesProvider)
        .items
        .where((b) => b.city?.toLowerCase() == city)
        .toList();
    if (_selectedCategorySlug == 'all') return list;
    return list.where((b) => b.categorySlug == _selectedCategorySlug).toList();
  }

  void _updateMarkers() {
    final businesses = _filteredBusinesses;
    final newMarkers = <Marker>{};

    for (final biz in businesses) {
      if (biz.latitude != null && biz.longitude != null) {
        final isSelected = _selectedBusiness?.id == biz.id;
        newMarkers.add(
          Marker(
            markerId: MarkerId(biz.id),
            position: LatLng(biz.latitude!, biz.longitude!),
            infoWindow: InfoWindow(
              title: biz.name,
              snippet:
                  '${biz.categoryName ?? biz.categorySlug} • ${biz.distanceText}',
            ),
            onTap: () {
              setState(() => _selectedBusiness = biz);
            },
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isSelected
                  ? BitmapDescriptor.hueMagenta
                  : _getCategoryHue(biz.categorySlug),
            ),
          ),
        );
      }
    }

    if (_currentPosition != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: _currentPosition!.target,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Search center'),
        ),
      );
    }

    setState(() => _markers = newMarkers);
  }

  double _getCategoryHue(String category) {
    switch (category) {
      case 'restaurant':
        return BitmapDescriptor.hueOrange;
      case 'grocery':
        return BitmapDescriptor.hueGreen;
      case 'medical':
        return BitmapDescriptor.hueRed;
      case 'salon':
        return BitmapDescriptor.hueViolet;
      case 'hardware':
      case 'electrician':
      case 'plumber':
        return BitmapDescriptor.hueBlue;
      default:
        return BitmapDescriptor.hueCyan;
    }
  }

  void _openBusinessDetail(Business biz) {
    if (biz.categorySlug == 'electrician' ||
        biz.categorySlug == 'plumber' ||
        biz.categorySlug == 'carpenter') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ServiceProScreen(business: biz)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BusinessDetailScreen(businessId: biz.id),
        ),
      );
    }
  }

  void _openDirections(Business biz) async {
    final lat = biz.latitude;
    final lng = biz.longitude;
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Directions are unavailable because this listing has no coordinates.',
          ),
        ),
      );
      return;
    }
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Directions to ${biz.name}')));
      }
    }
  }

  void _centerOnUser() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      _hasGpsFix = true;
      _updateMapPosition(position.latitude, position.longitude);
      await _loadNearbyBusinesses(position.latitude, position.longitude);
    } catch (_) {
      if (!mounted) return;
      _useDefaultLocation();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS unavailable. Searching the selected city center.'),
        ),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    if (!_mapController.isCompleted) _mapController.complete(controller);
    _mapControllerInstance = controller;
    _updateMarkers();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(mapBusinessesProvider);
    final businesses = _filteredBusinesses;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nearby Map',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.mainText,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '${ref.watch(appLocationProvider).displayName} (5 km radius)',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          // View Switcher: Radar / Satellite Map
          IconButton(
            icon: Icon(
              _useRadarView ? Icons.map_rounded : Icons.radar_rounded,
              color: AppTheme.primary,
            ),
            tooltip: _useRadarView ? 'Show Map Tiles' : 'Show Radar View',
            onPressed: () {
              setState(() => _useRadarView = !_useRadarView);
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.my_location_rounded,
              color: AppTheme.primary,
            ),
            onPressed: _centerOnUser,
            tooltip: 'Center on Me',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Primary Map View or Interactive Radar Canvas
          if (!_useRadarView && _currentPosition != null)
            GoogleMap(
              initialCameraPosition: _currentPosition!,
              onMapCreated: _onMapCreated,
              markers: _markers,
              myLocationEnabled: _hasGpsFix,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            )
          else
            _buildInteractiveRadarCanvas(businesses),

          // Top Floating Category Carousel
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: _buildCategoryCarousel(),
          ),

          // Floating Center Button with Radar Ripple
          Positioned(
            right: 16,
            bottom: _selectedBusiness != null ? 220 : 32,
            child: FloatingActionButton.small(
              heroTag: 'center_gps_fab',
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: _centerOnUser,
              child: const Icon(
                Icons.gps_fixed_rounded,
                color: AppTheme.primary,
              ),
            ),
          ),

          // Floating Bottom Business Preview Card
          if (_selectedBusiness != null)
            Positioned(
              bottom: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                top: false,
                child: _buildBottomBusinessCard(_selectedBusiness!),
              ),
            ),

          // Loading overlay
          if (!_isLoading && (_error != null || businesses.isEmpty))
            Positioned(
              top: 76,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error ?? 'No listed shops in this city within 5 km of the search position.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: _useDefaultLocation,
                        child: const Text('Search selected city'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isLoading)
            const Positioned(
              top: 76,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryCarousel() {
    final categories = ref.watch(categoriesProvider);
    if (categories.error != null)
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => ref.read(categoriesProvider.notifier).load(),
          child: const Text('Retry categories'),
        ),
      );
    final items = <Map<String, dynamic>>[
      {'slug': 'all', 'name': 'All', 'icon': Icons.tune_rounded},
      ...categories.items.map(
        (c) => {
          'slug': c.slug,
          'name': c.name,
          'icon': CategoriesScreen.getCategoryIcon(c.slug),
        },
      ),
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = items[index];
          final slug = cat['slug'] as String;
          final isSelected = _selectedCategorySlug == slug;

          return GestureDetector(
            key: ValueKey('map_category_$slug'),
            onTap: () {
              setState(() {
                _selectedCategorySlug = slug;
                _selectedBusiness = null;
              });
              final center = _currentPosition?.target;
              if (center != null)
                _loadNearbyBusinesses(center.latitude, center.longitude);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isSelected ? 0.15 : 0.04,
                    ),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat['icon'] as IconData,
                    size: 16,
                    color: isSelected ? Colors.white : AppTheme.secondaryText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cat['name'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : AppTheme.mainText,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBusinessCard(Business biz) {
    final rating = biz.rating;
    final reviewCount = biz.reviewCount;
    final distanceText = biz.distanceText;
    final categoryName = biz.categoryName ?? biz.categorySlug;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Business Category Icon Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2457D6), Color(0xFF0F766E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  biz.name.isNotEmpty ? biz.name[0] : 'G',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Title, rating, distance
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            biz.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.mainText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (biz.verificationStatus == 'verified') ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: Color(0xFF2457D6),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 15,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          rating == null
                              ? 'Not rated'
                              : '${rating.toStringAsFixed(1)}${reviewCount == null ? '' : ' ($reviewCount)'}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• $categoryName',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$distanceText • ${biz.locality ?? biz.city ?? ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // Dismiss X button
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.secondaryText,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _selectedBusiness = null),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Action CTAs
          Row(
            children: [
              // Directions CTA
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _openDirections(biz),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.directions_rounded,
                          size: 18,
                          color: AppTheme.mainText,
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Directions',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.mainText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // View Profile / Book CTA
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _openBusinessDetail(biz),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_pin_circle_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'View Profile',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

  Widget _buildInteractiveRadarCanvas(List<Business> businesses) {
    return AnimatedBuilder(
      animation: _radarAnimController,
      builder: (context, child) {
        return Stack(
          children: [
            // Radar Background Canvas with Concentric Distance Rings
            CustomPaint(
              size: Size.infinite,
              painter: _RadarMapPainter(
                sweepProgress: _radarAnimController.value,
              ),
            ),

            // User Location Center Dot
            Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),

            // Business Marker Pins Placed in Polar Coordinates
            ...businesses.asMap().entries.map((entry) {
              final biz = entry.value;
              final isSelected = _selectedBusiness?.id == biz.id;

              final center = _currentPosition?.target;
              if (center == null ||
                  biz.latitude == null ||
                  biz.longitude == null)
                return const SizedBox.shrink();
              // Project actual coordinates around the search center. Never invent positions.
              final north = (biz.latitude! - center.latitude) * 111320;
              final east =
                  (biz.longitude! - center.longitude) *
                  111320 *
                  math.cos(center.latitude * math.pi / 180);

              return Align(
                alignment: Alignment(
                  (east / 5000).clamp(-0.85, 0.85),
                  (-north / 5000).clamp(-0.85, 0.85),
                ),
                child: GestureDetector(
                  key: ValueKey('radar_business_${biz.id}'),
                  onTap: () {
                    setState(() => _selectedBusiness = biz);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pin Chip
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primary : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFFCBD5E1),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: isSelected ? 8 : 4,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getCategoryIcon(biz.categorySlug),
                              size: 13,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              biz.name.split(' ').first,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.mainText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Pin arrow tip
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primary : Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'electrician':
        return Icons.bolt_rounded;
      case 'hardware':
        return Icons.hardware_rounded;
      case 'medical':
        return Icons.local_pharmacy_rounded;
      case 'grocery':
        return Icons.local_grocery_store_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'salon':
        return Icons.content_cut_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }
}

/// Custom painter for radar sweep & concentric distance rings
class _RadarMapPainter extends CustomPainter {
  final double sweepProgress;

  _RadarMapPainter({required this.sweepProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.44;

    // Background gradient fill
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius * 1.3));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Concentric Distance Rings (500m, 1km, 2km)
    final ringPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final rings = [0.3, 0.6, 0.9];
    for (final r in rings) {
      canvas.drawCircle(center, maxRadius * r, ringPaint);
    }

    // Grid crosshairs
    final crosshairPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius),
      Offset(center.dx, center.dy + maxRadius),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      crosshairPaint,
    );

    // Radar beam sweep
    final sweepAngle = sweepProgress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: FractionalOffset.center,
        startAngle: 0.0,
        endAngle: 2 * math.pi,
        colors: [
          const Color(0xFF2457D6).withValues(alpha: 0.0),
          const Color(0xFF2457D6).withValues(alpha: 0.15),
        ],
        stops: const [0.85, 1.0],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarMapPainter oldDelegate) {
    return oldDelegate.sweepProgress != sweepProgress;
  }
}
