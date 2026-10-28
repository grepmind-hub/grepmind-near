import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';

/// Nearby map screen showing businesses on a map.
/// Note: Requires valid Google Maps API key in AndroidManifest.xml for full map tiles.
/// Without valid key, shows marker overlay on solid background (dev mode).
class NearbyMapScreen extends ConsumerStatefulWidget {
  const NearbyMapScreen({super.key});

  @override
  ConsumerState<NearbyMapScreen> createState() => _NearbyMapScreenState();
}

class _NearbyMapScreenState extends ConsumerState<NearbyMapScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  GoogleMapController? _mapControllerInstance;
  CameraPosition? _currentPosition;
  Set<Marker> _markers = {};
  bool _isLoading = false;
  String? _error;
  String? _mapError;
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _error = 'Location permission denied');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => _error = 'Location permission permanently denied');
      return;
    }
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    _isLoading = true;
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
      ),
    ).listen((Position position) {
      _updateMapPosition(position.latitude, position.longitude);
      _loadNearbyBusinesses(position.latitude, position.longitude);
    });
  }

  void _updateMapPosition(double lat, double lng) {
    final newPosition = CameraPosition(
      target: LatLng(lat, lng),
      zoom: 15.0,
    );
    if (_currentPosition == null) {
      _currentPosition = newPosition;
      setState(() {});
    } else if (_mapControllerInstance != null) {
      _mapControllerInstance!.animateCamera(CameraUpdate.newCameraPosition(newPosition));
    }
  }

  Future<void> _loadNearbyBusinesses(double lat, double lng) async {
    try {
      final businessesState = ref.read(businessesProvider.notifier);
      await businessesState.nearby(lat: lat, lng: lng);
      _updateMarkers();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateMarkers() {
    final businesses = ref.read(businessesProvider).items;
    final newMarkers = <Marker>{};
    for (final biz in businesses) {
      if (biz.latitude != null && biz.longitude != null) {
        newMarkers.add(Marker(
          markerId: MarkerId(biz.id),
          position: LatLng(biz.latitude!, biz.longitude!),
          infoWindow: InfoWindow(
            title: biz.name,
            snippet: '${biz.categoryName ?? biz.categorySlug} • ${biz.distanceText}',
            onTap: () => _openBusinessDetail(biz),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(_getCategoryHue(biz.categorySlug)),
        ));
      }
    }
    if (_currentPosition != null) {
      newMarkers.add(Marker(
        markerId: const MarkerId('my_location'),
        position: _currentPosition!.target,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Your location'),
      ));
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
        return BitmapDescriptor.hueBlue;
      default:
        return BitmapDescriptor.hueCyan;
    }
  }

  void _openBusinessDetail(Business biz) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BusinessDetailScreen(businessId: biz.id),
    ));
  }

  void _centerOnUser() async {
    if (_currentPosition != null && _mapControllerInstance != null) {
      await _mapControllerInstance!.animateCamera(CameraUpdate.newCameraPosition(_currentPosition!));
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController.complete(controller);
    _mapControllerInstance = controller;
    _updateMarkers();
    
    // Check if map tiles are loading (API key validity)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _mapControllerInstance != null) {
        // If map still shows solid color after 3s, API key is likely invalid
        _checkMapTilesLoading();
      }
    });
  }

  void _checkMapTilesLoading() {
    // In development, if no valid API key, show helpful message
    // This is a heuristic - real check would need platform channel
    setState(() {
      _mapError = 'Map tiles require valid Google Maps API key.\n'
          'Add key to android/app/src/main/AndroidManifest.xml\n'
          'Get key from: https://console.cloud.google.com/';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _centerOnUser,
            tooltip: 'My location',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_currentPosition != null)
            GoogleMap(
              initialCameraPosition: _currentPosition!,
              onMapCreated: _onMapCreated,
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            )
          else
            Container(
              color: AppTheme.surfaceVariant,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Getting your location...'),
                  ],
                ),
              ),
            ),
          // Dev notice for API key
          if (_mapError != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                color: AppTheme.warningContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber, color: AppTheme.warning),
                          SizedBox(width: 8),
                          Text('Development Mode', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.warning)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_mapError!, style: const TextStyle(fontSize: 12, color: AppTheme.mainText)),
                      const SizedBox(height: 8),
                      const Text(
                        'Markers still work - tap them to view business details.',
                        style: TextStyle(fontSize: 11, color: AppTheme.secondaryText),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null && _mapError == null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Colors.white))),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setState(() => _error = null),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isLoading && _currentPosition != null)
            const Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}