import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:grepmind_mobile/core/data/category_listings_data.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/service_pro_screen.dart';
import 'package:grepmind_mobile/core/screens/categories_screen.dart';
import 'package:grepmind_mobile/core/theme/abashyaka_colors.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/utils/category_sample_image.dart';
import 'package:grepmind_mobile/core/widgets/category_placeholder.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_background.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_painter.dart';
import 'package:grepmind_mobile/core/widgets/premium_network_image.dart';
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
    this.useDeviceLocation = false,
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

  // Selected Filters
  String _selectedCategorySlug = 'all';
  String _typeFilter = 'all'; // 'all', 'shops', 'services'
  bool _onlyOpenNow = false;
  int _radiusKm = 5;
  bool _showResultsList = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _useDefaultLocation();
    });

    if (widget.useDeviceLocation) {
      _requestLocationPermission();
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
    if (location.cityName.isEmpty || location.latitude == 0) {
      ref.read(appLocationProvider.notifier).loadDefaultLocation().then((_) {
        if (!mounted) return;
        final updated = ref.read(appLocationProvider);
        final lat = (updated.latitude != 0) ? updated.latitude : 20.6120;
        final lng = (updated.longitude != 0) ? updated.longitude : 86.0465;
        _updateMapPosition(lat, lng);
        _loadNearbyBusinesses(lat, lng);
      });
      return;
    }
    final defLat = (location.latitude != 0) ? location.latitude : 20.6120;
    final defLng = (location.longitude != 0) ? location.longitude : 86.0465;
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
    if (city.isEmpty && lat == 0 && lng == 0) {
      if (mounted) {
        setState(() {
          _error = 'Please select a city in Explore to browse nearby.';
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final businessesState = ref.read(mapBusinessesProvider.notifier);
      await businessesState.nearby(
        lat: lat,
        lng: lng,
        radiusM: _radiusKm * 1000,
        city: city.isEmpty ? null : city,
        categorySlug: _selectedCategorySlug == 'all'
            ? null
            : _selectedCategorySlug,
      );
      if (!mounted || sequence != _loadSequence) return;
      if (ref.read(mapBusinessesProvider).error != null) {
        throw StateError('Nearby lookup failed');
      }

      // Automatically select closest business if none selected
      final businesses = _filteredBusinesses;
      setState(
        () => _selectedBusiness = businesses.isEmpty ? null : businesses.first,
      );
      _updateMarkers();
    } catch (e) {
      if (mounted && sequence == _loadSequence) {
        setState(() {
          _error = 'Unable to load nearby shops. Please try again.';
          _selectedBusiness = null;
          _markers = {};
        });
      }
    } finally {
      if (mounted && sequence == _loadSequence) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Business> get _filteredBusinesses {
    final all = ref.watch(mapBusinessesProvider).items;

    return all.where((b) {
      // 1. Entity type: All, Shops, or Services
      final isServiceOrPro = b.isServiceProvider ||
          b.categoryNatureLabel == 'Transport' ||
          b.categoryNatureLabel == 'Healthcare' ||
          b.categoryNatureLabel == 'Education' ||
          b.categoryNatureLabel == 'Service' ||
          b.categoryNatureLabel == 'Auto Care' ||
          b.categoryNatureLabel == 'Events' ||
          b.categoryNatureLabel == 'Construction';

      if (_typeFilter == 'shops' && isServiceOrPro) {
        return false;
      }
      if (_typeFilter == 'services' && !isServiceOrPro) {
        return false;
      }
      // 2. Category slug filter
      if (_selectedCategorySlug != 'all' &&
          !CategoryListingsData.matchesCategory(
              b.categorySlug, _selectedCategorySlug)) {
        return false;
      }
      // 3. Open Now filter
      if (_onlyOpenNow && !b.isOpenNow) {
        return false;
      }
      return true;
    }).toList();
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
                  : (biz.shouldOpenServiceProfile
                        ? BitmapDescriptor.hueAzure
                        : _getCategoryHue(biz.categorySlug)),
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
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
    if (biz.shouldOpenServiceProfile) {
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

  Future<void> _setSearchRadius(int radiusKm) async {
    if (radiusKm == _radiusKm || !mounted) return;
    setState(() => _radiusKm = radiusKm);
    final loc = ref.read(appLocationProvider);
    final lat = _currentPosition?.target.latitude ?? loc.latitude;
    final lng = _currentPosition?.target.longitude ?? loc.longitude;
    await _loadNearbyBusinesses(lat, lng);
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
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission was not granted');
      }
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

    final palette = context.abashyaka;
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.card,
        elevation: 0,
        centerTitle: false,
        flexibleSpace: const FluidWaveBackground(
          variant: FluidWaveVariant.compact,
        ),
        title: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nearby Map',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AbashyakaColors.pureWhite,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${ref.watch(appLocationProvider).displayName} · $_radiusKm km radius',
                style: TextStyle(
                  fontSize: 11,
                  color: AbashyakaColors.pureWhite.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // View Switcher: Radar / Satellite Map
          IconButton(
            icon: Icon(
              _useRadarView ? Icons.map_rounded : Icons.radar_rounded,
              color: AbashyakaColors.pureWhite,
            ),
            tooltip: _useRadarView ? 'Show Map Tiles' : 'Show Radar View',
            onPressed: () {
              setState(() => _useRadarView = !_useRadarView);
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.my_location_rounded,
              color: AbashyakaColors.pureWhite,
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

          // Top Floating Type Filter Bar (All Places, Shops, Services, Open Now)
          Positioned(top: 10, left: 0, right: 0, child: _buildTypeFilterBar()),

          // Floating Adaptive Category Carousel
          Positioned(
            top: 52,
            left: 0,
            right: 0,
            child: _buildCategoryCarousel(),
          ),

          // Search Radius & Results Count Controls
          Positioned(
            top: 98,
            left: 14,
            right: 14,
            child: _buildResultsControls(businesses.length),
          ),

          if (_showResultsList)
            Positioned(
              top: 144,
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildResultsList(businesses),
            ),

          // Floating Center Button with Radar Ripple
          if (!_showResultsList)
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
                  color: AbashyakaColors.signatureTeal,
                ),
              ),
            ),

          // Floating Bottom Business Preview Card
          if (!_showResultsList && _selectedBusiness != null)
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
              top: 148,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error ??
                            'No approved shops or services are within $_radiusKm km of this search point.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: _useDefaultLocation,
                        child: Text(
                          'Search ${ref.watch(appLocationProvider).cityName} center',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isLoading)
            const Positioned(
              top: 148,
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

  Widget _buildTypeFilterBar() {
    final typeFilters = [
      ('all', 'All Places', Icons.explore_rounded),
      ('shops', '🛍️ Shops', null),
      ('services', '🛠️ Services', null),
      ('open_now', '🕒 Open Now', null),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: typeFilters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = typeFilters[index];
          final key = item.$1;
          final label = item.$2;
          final icon = item.$3;

          final bool isSelected;
          if (key == 'open_now') {
            isSelected = _onlyOpenNow;
          } else {
            isSelected = _typeFilter == key;
          }

          return InkWell(
            key: ValueKey('nearby_filter_$key'),
            onTap: () {
              setState(() {
                if (key == 'open_now') {
                  _onlyOpenNow = !_onlyOpenNow;
                } else {
                  _typeFilter = key;
                  _selectedCategorySlug = 'all'; // reset category sub-filter cleanly
                }
                final filtered = _filteredBusinesses;
                if (_selectedBusiness != null &&
                    !filtered.any((b) => b.id == _selectedBusiness!.id)) {
                  _selectedBusiness = filtered.isNotEmpty
                      ? filtered.first
                      : null;
                }
              });
              _updateMarkers();
            },
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? (context.abashyaka.isDark
                          ? context.abashyaka.accentSurface
                          : const Color(0xFFE6F7F7))
                    : context.abashyaka.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected
                      ? context.abashyaka.accent
                      : context.abashyaka.border,
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? AbashyakaColors.signatureTeal.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 15,
                      color: isSelected
                          ? context.abashyaka.accent
                          : context.abashyaka.textSecondary,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isSelected
                          ? context.abashyaka.accent
                          : context.abashyaka.textPrimary,
                      letterSpacing: -0.2,
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

  Widget _buildResultsControls(int count) {
    String typeLabel = 'places';
    if (_typeFilter == 'shops') typeLabel = 'shops';
    if (_typeFilter == 'services') typeLabel = 'services';
    final isAll = _selectedCategorySlug == 'all';

    return Row(
      children: [
        // 1. Radius Dropdown Selector
        Container(
          height: 38,
          padding: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            color: context.abashyaka.card,
            border: Border.all(color: context.abashyaka.border),
            borderRadius: BorderRadius.circular(19),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: const ValueKey('nearby_radius_selector'),
              value: _radiusKm,
              isDense: true,
              borderRadius: BorderRadius.circular(14),
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              selectedItemBuilder: (context) => [
                for (final radius in const [1, 3, 5, 10, 20, 50])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.radar_rounded,
                        size: 17,
                        color: AbashyakaColors.signatureTeal,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Within $radius km',
                        style: const TextStyle(
                          color: AbashyakaColors.premiumObsidian,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
              items: [
                for (final radius in const [1, 3, 5, 10, 20, 50])
                  DropdownMenuItem(value: radius, child: Text('$radius km')),
              ],
              onChanged: (radius) {
                if (radius != null) _setSearchRadius(radius);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 2. Count & Filter Summary Badge
        Expanded(
          child: Container(
            height: 38,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: context.abashyaka.card,
              border: Border.all(color: context.abashyaka.border),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              '$count $typeLabel${isAll ? ' · All' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.abashyaka.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 3. List / Map view toggle
        IconButton.filledTonal(
          key: const ValueKey('nearby_list_view_toggle'),
          tooltip: _showResultsList ? 'Show map' : 'Show all results',
          onPressed: () => setState(() => _showResultsList = !_showResultsList),
          icon: Icon(
            _showResultsList ? Icons.map_outlined : Icons.list_rounded,
          ),
          style: IconButton.styleFrom(
            backgroundColor: context.abashyaka.card,
            foregroundColor: context.abashyaka.accent,
            side: BorderSide(color: context.abashyaka.border),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsList(List<Business> businesses) {
    return Container(
      color: context.abashyaka.canvas,
      child: businesses.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE6F7F7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.filter_alt_off_rounded,
                        size: 36,
                        color: AbashyakaColors.signatureTeal,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No matching places nearby',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AbashyakaColors.premiumObsidian,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Try resetting your shop/service filters or expanding search radius.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AbashyakaColors.graphiteCharcoal,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _typeFilter = 'all';
                          _selectedCategorySlug = 'all';
                          _onlyOpenNow = false;
                        });
                        _updateMarkers();
                      },
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: const Text('Show all nearby'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AbashyakaColors.signatureTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: businesses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final business = businesses[index];
                final isService = business.shouldOpenServiceProfile;
                return Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  color: Colors.white,
                  child: ListTile(
                    key: ValueKey('nearby_result_${business.id}'),
                    minVerticalPadding: 12,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 84,
                        height: 68,
                        child: _businessThumbnail(business),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            business.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AbashyakaColors.premiumObsidian,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F7F7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AbashyakaColors.metallicTeal.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            business.categoryNatureLabel,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AbashyakaColors.signatureTeal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 3),
                        Text(
                          '${business.categoryName ?? business.categorySlug} · ${business.distanceText}${business.locality == null ? '' : ' · ${business.locality}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AbashyakaColors.graphiteCharcoal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              isService
                                  ? 'Book Service'
                                  : business.shopActionLabel,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AbashyakaColors.signatureTeal,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: AbashyakaColors.signatureTeal,
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.secondaryText,
                    ),
                    onTap: () => _openBusinessDetail(business),
                  ),
                );
              },
            ),
    );
  }

  Widget _businessThumbnail(Business business) {
    final coverPhotoUrl = business.coverPhotoUrl?.trim();
    final fallback = CategorySampleImage(
      index: categorySampleIndex(
        business.categorySlug,
        business.categoryName ?? business.categorySlug,
      ),
    );
    if (coverPhotoUrl == null || coverPhotoUrl.isEmpty) {
      return fallback;
    }
    return PremiumNetworkImage(
      imageUrl: apiClient.resolveMediaUrl(coverPhotoUrl),
      errorWidget: fallback,
    );
  }

  Widget _buildCategoryCarousel() {
    final categories = ref.watch(categoriesProvider);
    if (categories.error != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => ref.read(categoriesProvider.notifier).load(),
          child: const Text('Retry categories'),
        ),
      );
    }
    final filteredCategories = categories.items.where((c) {
      if (_typeFilter == 'all') return true;
      final isService = c.slug == 'services' ||
          c.slug == 'service' ||
          c.slug == 'cab-auto' ||
          c.slug == 'doctors' ||
          c.slug == 'salon' ||
          c.slug == 'fitness' ||
          c.slug == 'education' ||
          c.slug == 'events' ||
          c.slug == 'automobile' ||
          c.slug == 'construction' ||
          c.slug == 'hotels';
      if (_typeFilter == 'services') return isService;
      if (_typeFilter == 'shops') return !isService;
      return true;
    });

    final items = <Map<String, dynamic>>[
      {'slug': 'all', 'name': 'All', 'icon': Icons.tune_rounded},
      ...filteredCategories.map(
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
        separatorBuilder: (_, _) => const SizedBox(width: 8),
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
              final loc = ref.read(appLocationProvider);
              final lat = _currentPosition?.target.latitude ?? loc.latitude;
              final lng = _currentPosition?.target.longitude ?? loc.longitude;
              _loadNearbyBusinesses(lat, lng);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFE6F7F7)
                    : (slug == 'all'
                          ? const Color(0xFFF8FAFC)
                          : CategoriesScreen.getCategoryBackgroundColor(slug)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AbashyakaColors.metallicTeal
                      : const Color(0xFFE2E8F0),
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? AbashyakaColors.signatureTeal.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.04),
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
                    color: isSelected
                        ? AbashyakaColors.signatureTeal
                        : (slug == 'all'
                              ? AbashyakaColors.signatureTeal
                              : CategoriesScreen.getCategoryColor(slug)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cat['name'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AbashyakaColors.signatureTeal
                          : AbashyakaColors.graphiteCharcoal,
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

  IconData _getActionIcon(Business biz) {
    final slug = biz.categorySlug.toLowerCase().trim();
    switch (slug) {
      case 'cab_auto':
      case 'transport':
      case 'cab':
      case 'auto':
        return Icons.local_taxi_rounded;
      case 'doctors':
      case 'doctor':
      case 'clinic':
      case 'hospital':
        return Icons.calendar_month_rounded;
      case 'education':
      case 'coaching':
      case 'school':
      case 'college':
        return Icons.school_outlined;
      case 'food':
      case 'restaurant':
      case 'cafe':
      case 'bakery':
        return Icons.restaurant_menu_rounded;
      case 'hotels_stays':
      case 'hotel':
      case 'stays':
        return Icons.hotel_rounded;
      case 'beauty_salon':
      case 'salon':
      case 'beauty':
        return Icons.spa_rounded;
      case 'fitness_wellness':
      case 'fitness':
      case 'gym':
        return Icons.fitness_center_rounded;
      case 'services':
      case 'service':
      case 'electrician':
      case 'plumber':
      case 'carpenter':
      case 'ac_mechanic':
      case 'cleaning':
      case 'automobile':
      case 'automotive':
        return Icons.handyman_rounded;
      case 'grocery':
      case 'kirana':
        return Icons.shopping_basket_rounded;
      case 'medicines':
      case 'medical':
      case 'pharmacy':
        return Icons.medication_rounded;
      case 'events_catering':
      case 'events':
      case 'catering':
        return Icons.celebration_rounded;
      case 'construction':
      case 'hardware':
        return Icons.foundation_rounded;
      case 'home_painting_decor':
      case 'painting':
        return Icons.format_paint_rounded;
      case 'home_furniture':
      case 'furniture':
        return Icons.chair_rounded;
      case 'electronics':
        return Icons.devices_rounded;
      case 'fashion':
        return Icons.checkroom_rounded;
      default:
        return biz.isServiceProvider
            ? Icons.handyman_rounded
            : Icons.storefront_rounded;
    }
  }

  Widget _buildBottomBusinessCard(Business biz) {
    final rating = biz.rating;
    final reviewCount = biz.reviewCount;
    final distanceText = biz.distanceText;
    final categoryName = biz.categoryName ?? biz.categorySlug;
    final isService = biz.shouldOpenServiceProfile;
    final palette = context.abashyaka;

    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
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
              // Business Category Icon Avatar with CategoryThemedPlaceholder
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: (biz.coverPhotoUrl?.isNotEmpty ?? false)
                      ? PremiumNetworkImage(
                          imageUrl: apiClient.resolveMediaUrl(biz.coverPhotoUrl!),
                          errorWidget: CategoryThemedPlaceholder(
                            categorySlug: biz.categorySlug,
                            categoryName: biz.categoryName,
                            businessName: biz.name,
                            isAvatar: true,
                          ),
                        )
                      : CategoryThemedPlaceholder(
                          categorySlug: biz.categorySlug,
                          categoryName: biz.categoryName,
                          businessName: biz.name,
                          isAvatar: true,
                        ),
                ),
              ),

              const SizedBox(width: 12),

              // Title, rating, distance, status
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
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: palette.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (biz.verificationStatus == 'verified') ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: palette.accent,
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
                          color: AbashyakaColors.metallicGold,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          rating == null
                              ? 'Not rated'
                              : '${rating.toStringAsFixed(1)}${reviewCount == null ? '' : ' ($reviewCount)'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '• $categoryName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '$distanceText • ${biz.locality ?? biz.city ?? ''}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: palette.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F7F7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AbashyakaColors.metallicTeal.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            biz.categoryNatureLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AbashyakaColors.signatureTeal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: biz.isOpenNow
                                ? const Color(0xFFE6F7F7)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            biz.isOpenNow ? 'Open now' : 'Closed',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: biz.isOpenNow
                                  ? AbashyakaColors.signatureTeal
                                  : AbashyakaColors.graphiteCharcoal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Dismiss X button
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: palette.textSecondary,
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
                      side: BorderSide(color: palette.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _openDirections(biz),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.directions_rounded,
                          size: 18,
                          color: palette.accent,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Directions',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: palette.accent,
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

              // Contextual Action: Book Service for services, Shop Now / View Store for shops
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: InkWell(
                    onTap: () => _openBusinessDetail(biz),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AbashyakaColors.signatureTeal,
                            AbashyakaColors.metallicTeal,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AbashyakaColors.signatureTeal
                                .withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getActionIcon(biz),
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              biz.primaryActionLabel,
                              style: const TextStyle(
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
                  color: AbashyakaColors.signatureTeal,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AbashyakaColors.signatureTeal.withValues(alpha: 0.4),
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

              final loc = ref.watch(appLocationProvider);
              final centerLat =
                  _currentPosition?.target.latitude ?? loc.latitude;
              final centerLng =
                  _currentPosition?.target.longitude ?? loc.longitude;
              if (biz.latitude == null || biz.longitude == null) {
                return const SizedBox.shrink();
              }
              // Project actual coordinates around the search center. Never invent positions.
              final north = (biz.latitude! - centerLat) * 111320;
              final east =
                  (biz.longitude! - centerLng) *
                  111320 *
                  math.cos(centerLat * math.pi / 180);

              return Align(
                alignment: Alignment(
                  (east / (_radiusKm * 1000)).clamp(-0.85, 0.85),
                  (-north / (_radiusKm * 1000)).clamp(-0.85, 0.85),
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
                          color: isSelected
                              ? AbashyakaColors.signatureTeal
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : CategoriesScreen.getCategoryColor(
                                    biz.categorySlug,
                                  ).withValues(alpha: 0.5),
                            width: isSelected ? 2 : 1.5,
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
                              CategoriesScreen.getCategoryIcon(
                                biz.categorySlug,
                              ),
                              size: 13,
                              color: isSelected
                                  ? Colors.white
                                  : CategoriesScreen.getCategoryColor(
                                      biz.categorySlug,
                                    ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              biz.name.split(' ').first,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? Colors.white
                                    : AbashyakaColors.premiumObsidian,
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
                          color: isSelected
                              ? AbashyakaColors.signatureTeal
                              : CategoriesScreen.getCategoryColor(
                                  biz.categorySlug,
                                ),
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

    // Radar beam sweep with Abashyaka Metallic Teal
    final sweepAngle = sweepProgress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: FractionalOffset.center,
        colors: [
          AbashyakaColors.metallicTeal.withValues(alpha: 0.0),
          AbashyakaColors.metallicTeal.withValues(alpha: 0.18),
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
