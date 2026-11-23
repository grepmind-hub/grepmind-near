import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/features/branding/abashyaka_theme.dart';
import 'package:grepmind_mobile/features/location/serviceability_service.dart';

class LocationSelectionSheet extends ConsumerStatefulWidget {
  const LocationSelectionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LocationSelectionSheet(),
    );
  }

  @override
  ConsumerState<LocationSelectionSheet> createState() =>
      _LocationSelectionSheetState();
}

class _LocationSelectionSheetState
    extends ConsumerState<LocationSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ServiceabilityService _serviceabilityService = ServiceabilityService();

  List<LocalitySummary> _localities = [];
  bool _loading = true;
  bool _checkingGps = false;

  // Unserviced location state
  bool _showOutsideServiceArea = false;
  String _unservicedPinCode = '';
  String _unservicedLocality = '';
  bool _notified = false;
  bool _notifying = false;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    setState(() => _loading = true);
    final results = await _serviceabilityService.fetchServiceableLocalities();
    if (mounted) {
      setState(() {
        _localities = results;
        _loading = false;
      });
    }
  }

  Future<void> _handleGpsLocation() async {
    // Show contextual primer dialog first
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AbashyakaTheme.lightMint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.my_location_rounded,
                color: AbashyakaTheme.actionGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Use Device Location',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AbashyakaTheme.carbon,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Abashyaka uses your location to discover nearby local merchants, show real-time delivery estimates, and connect you with verified local service professionals.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF4B5563),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'NOT NOW',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AbashyakaTheme.vibrantGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
            child: const Text(
              'ALLOW LOCATION',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() => _checkingGps = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location permission was denied. Please select your locality below.',
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

      final pos = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 6),
      );

      final check = await _serviceabilityService.checkServiceability(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      if (!check.serviceable) {
        setState(() {
          _showOutsideServiceArea = true;
          _unservicedPinCode = check.pinCode.isNotEmpty ? check.pinCode : 'GPS';
          _unservicedLocality = 'Current GPS Area';
          _notified = false;
        });
        return;
      }

      ref.read(appLocationProvider.notifier).setLocation(
            AppLocation(
              cityName: check.districtName.isNotEmpty
                  ? check.districtName
                  : 'Odisha',
              localityName: check.localityName.isNotEmpty
                  ? check.localityName
                  : 'Chhatia',
              localityId: check.localityId,
              latitude: pos.latitude,
              longitude: pos.longitude,
              activeBusinessCount: 15,
            ),
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Delivering to ${check.localityName}, ${check.districtName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: AbashyakaTheme.actionGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'GPS timed out or unavailable. Please choose your locality manually.',
            ),
            backgroundColor: const Color(0xFF374151),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingGps = false);
    }
  }

  Future<void> _handleManualPinSearch(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.length != 6 || int.tryParse(trimmed) == null) return;

    setState(() => _loading = true);
    final check = await _serviceabilityService.checkServiceability(
      pinCode: trimmed,
    );

    if (mounted) {
      if (check.serviceable) {
        ref.read(appLocationProvider.notifier).setLocation(
              AppLocation(
                cityName: check.districtName.isNotEmpty
                    ? check.districtName
                    : 'Odisha',
                localityName: check.localityName.isNotEmpty
                    ? check.localityName
                    : 'Chhatia',
                localityId: check.localityId,
                latitude: 20.6105,
                longitude: 86.0270,
                activeBusinessCount: 15,
              ),
            );
        Navigator.pop(context);
      } else {
        setState(() {
          _loading = false;
          _showOutsideServiceArea = true;
          _unservicedPinCode = trimmed;
          _unservicedLocality = 'PIN $trimmed';
          _notified = false;
        });
      }
    }
  }

  Future<void> _handleNotifyLead() async {
    setState(() => _notifying = true);
    await _serviceabilityService.notifyInterest(
      pinCode: _unservicedPinCode,
      localityName: _unservicedLocality,
    );
    if (mounted) {
      setState(() {
        _notifying = false;
        _notified = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLocation = ref.watch(appLocationProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Your Location',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AbashyakaTheme.carbon,
                    letterSpacing: -0.2,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  onPressed: () => Navigator.pop(context),
                  color: const Color(0xFF6B7280),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: _showOutsideServiceArea
                ? _buildOutsideServiceAreaView()
                : _buildSelectionView(currentLocation),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionView(AppLocation currentLocation) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _localities.where((loc) {
      if (query.isEmpty) return true;
      final matchName = loc.name.toLowerCase().contains(query);
      final matchDistrict = loc.districtName.toLowerCase().contains(query);
      final matchPin = loc.pinCodes.any((p) => p.contains(query));
      return matchName || matchDistrict || matchPin;
    }).toList();

    return Column(
      children: [
        // Search Input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
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
                    onChanged: (val) {
                      setState(() {});
                      if (val.trim().length == 6) {
                        _handleManualPinSearch(val.trim());
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: 'Enter 6-digit PIN code or locality...',
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
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    child: const Icon(
                      Icons.cancel_rounded,
                      color: Color(0xFF9CA3AF),
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),

        // GPS Use Current Location row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: InkWell(
            onTap: _checkingGps ? null : _handleGpsLocation,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AbashyakaTheme.lightMint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _checkingGps
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AbashyakaTheme.vibrantGreen,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.my_location_rounded,
                            color: AbashyakaTheme.actionGreen,
                            size: 20,
                          ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Use Current Location',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AbashyakaTheme.carbon,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'High-accuracy GPS location detection',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9CA3AF),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),

        const Divider(color: Color(0xFFF3F4F6), height: 1),

        // Locality List Section
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Available Service Areas',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                '${filtered.length} locations',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AbashyakaTheme.vibrantGreen,
                  ),
                )
              : filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.location_off_outlined,
                              size: 44,
                              color: Color(0xFF9CA3AF),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No coverage for "${_searchController.text}"',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AbashyakaTheme.carbon,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Try searching another locality or PIN code.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _showOutsideServiceArea = true;
                                  _unservicedPinCode =
                                      _searchController.text.trim();
                                  _unservicedLocality =
                                      _searchController.text.trim();
                                  _notified = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AbashyakaTheme.vibrantGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 0,
                              ),
                              child: const Text('Check Coverage Status'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Color(0xFFF3F4F6), height: 1),
                      itemBuilder: (context, index) {
                        final loc = filtered[index];
                        final isSelected =
                            currentLocation.localityName.toLowerCase() ==
                                loc.name.toLowerCase();

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AbashyakaTheme.lightMint
                                  : const Color(0xFFF3F4F6),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.location_on_outlined,
                              color: isSelected
                                  ? AbashyakaTheme.vibrantGreen
                                  : const Color(0xFF6B7280),
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                loc.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: AbashyakaTheme.carbon,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (loc.deliveryEnabled)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AbashyakaTheme.lightMint,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Delivery Active',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: AbashyakaTheme.actionGreen,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3F2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Discovery Only',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFB42318),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${loc.districtName}, Odisha · ${loc.pinCodes.isNotEmpty ? loc.pinCodes.join(", ") : "Postal Zone"}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: AbashyakaTheme.vibrantGreen,
                                  size: 20,
                                )
                              : null,
                          onTap: () {
                            ref
                                .read(appLocationProvider.notifier)
                                .setLocation(
                                  AppLocation(
                                    cityName: loc.districtName,
                                    localityName: loc.name,
                                    localityId: loc.id,
                                    latitude: loc.latitude ?? 20.6105,
                                    longitude: loc.longitude ?? 86.0270,
                                    activeBusinessCount: 15,
                                  ),
                                );
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // Authoritative "Outside Service Area" 2027 screen per PP-02 Spec
  Widget _buildOutsideServiceAreaView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        children: [
          // 3D Store Illustration with Pin
          Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                      color: AbashyakaTheme.warmPeach,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        size: 48,
                        color: AbashyakaTheme.actionGreen,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFD6AE)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: AbashyakaTheme.signatureOrange,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Coverage Boundary',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AbashyakaTheme.signatureOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Amber badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4ED),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Expanding our coverage',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AbashyakaTheme.signatureOrange,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Heading
          const Text(
            "We're not in your area just yet.",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AbashyakaTheme.deepEmerald,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Body text
          const Text(
            'Abashyaka is growing neighbourhood by neighbourhood. We’re working to bring trusted local shops and convenient services closer to you.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          // Selected Location Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF6B7280),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your selected location',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _unservicedPinCode.isNotEmpty
                            ? 'PIN $_unservicedPinCode · Outside service area'
                            : 'Currently outside our service area',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Primary Button: Notify me when available
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _notified || _notifying ? null : _handleNotifyLead,
              style: ElevatedButton.styleFrom(
                backgroundColor: _notified
                    ? AbashyakaTheme.actionGreen
                    : AbashyakaTheme.vibrantGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                elevation: 0,
              ),
              child: _notifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _notified
                          ? '✓ We will notify you!'
                          : 'Notify me when available',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 12),

          // Secondary Button: Change location
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _showOutsideServiceArea = false;
                  _searchController.clear();
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AbashyakaTheme.actionGreen,
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Change location',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
