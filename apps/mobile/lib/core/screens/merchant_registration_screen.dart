import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Screen 19: Merchant Registration & Claim Screen
///
/// Onboarding funnel for local shop owners and skilled service professionals
/// to either register a new enterprise or claim an existing unverified directory listing.
class MerchantRegistrationScreen extends ConsumerStatefulWidget {
  const MerchantRegistrationScreen({super.key, this.initialMode = 0});

  /// 0 = Register New, 1 = Claim Existing Listing
  final int initialMode;

  @override
  ConsumerState<MerchantRegistrationScreen> createState() =>
      _MerchantRegistrationScreenState();
}

class _CategoryLoadError extends StatelessWidget {
  const _CategoryLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.cloud_off_outlined),
      title: const Text('Categories could not be loaded'),
      subtitle: const Text('Check your connection and try again.'),
      trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
    ),
  );
}

class _ClaimRequestSheet extends StatefulWidget {
  const _ClaimRequestSheet({required this.businessName});

  final String businessName;

  @override
  State<_ClaimRequestSheet> createState() => _ClaimRequestSheetState();
}

class _ClaimRequestSheetState extends State<_ClaimRequestSheet> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.of(context).viewInsets.bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Request ownership review',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            widget.businessName,
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Signing in verifies your Grepmind account, not control of this business. An administrator will review your claim before any ownership or access changes.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('claim_statement'),
            controller: _messageController,
            onChanged: (_) => setState(() {}),
            minLines: 3,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'How are you connected to this business?',
              hintText: 'Describe your role and how the review team can verify your claim.',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _messageController.text.trim().length < 10
                  ? null
                  : () =>
                        Navigator.pop(context, _messageController.text.trim()),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Submit for review'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedCategory,
    required this.classificationBySlug,
    required this.onSelected,
  });

  final List<Category> categories;
  final Category? selectedCategory;
  final Map<String, String> classificationBySlug;
  final ValueChanged<Category> onSelected;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.categories.where((category) {
      final group = widget.classificationBySlug[category.slug] ?? 'Other';
      final query = _query.trim().toLowerCase();
      return query.isEmpty ||
          category.name.toLowerCase().contains(query) ||
          category.slug.replaceAll('_', ' ').contains(query) ||
          group.toLowerCase().contains(query);
    }).toList();
    final groups = <String, List<Category>>{};
    for (final category in filtered) {
      final group = widget.classificationBySlug[category.slug] ?? 'Other';
      groups.putIfAbsent(group, () => []).add(category);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('merchant_category_search'),
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Search all ${widget.categories.length} categories',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No matching category. Try another search.'),
          )
        else
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
              child: Text(
                entry.key.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.secondaryText,
                ),
              ),
            ),
            ...entry.value.map((category) {
              final selected = category.slug == widget.selectedCategory?.slug;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected
                      ? AppTheme.primary.withValues(alpha: 0.06)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: ValueKey('merchant_category_${category.slug}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => widget.onSelected(category),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? AppTheme.primary : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (category.description?.isNotEmpty == true)
                                  Text(
                                    category.description!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.secondaryText,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_circle,
                              color: AppTheme.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
      ],
    );
  }
}

class _MerchantRegistrationScreenState
    extends ConsumerState<MerchantRegistrationScreen> {
  late int _mode; // 0 = Register New, 1 = Claim Existing
  int _currentStep = 0; // 0 = Category & Type, 1 = Basic Info, 2 = Location & Storefront, 3 = Operations

  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _businessNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _taglineController = TextEditingController();

  final _addressController = TextEditingController();
  final _localityController = TextEditingController();
  final _cityController = TextEditingController();
  final _pinController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  final _searchClaimController = TextEditingController();

  // Registration Selections
  String _enterpriseType = 'retail'; // retail, service_pro, food, wellness
  String? _selectedCategorySlug = 'hardware';
  String _selectedCategoryName = 'Hardware';
  String? _coverPhotoUrl;
  double? _businessLatitude;
  double? _businessLongitude;
  bool _isLocating = false;
  bool _isUploadingPhoto = false;
  bool _isUnorganized = false;
  String _operatingMode = 'both'; // store_only, home_only, both
  double _serviceRadiusKm = 6.0;
  String _hoursPreset = 'mon_sat'; // mon_sat, all_days, emergency

  bool _isSubmitting = false;
  bool _isSuccess = false;
  String _generatedAppId = '';

  // Claim listings are always loaded from the authenticated API.
  List<Map<String, dynamic>> _filteredClaimable = [];
  Timer? _claimSearchDebounce;
  int _claimSearchGeneration = 0;
  bool _claimSearchLoading = false;
  String? _claimSearchError;
  List<Map<String, dynamic>> _myClaimRequests = [];

  static const Map<String, String> _classificationBySlug = {
    'grocery': 'Retail & shopping',
    'hardware': 'Retail & shopping',
    'medical': 'Health & wellness',
    'restaurant': 'Food & hospitality',
    'salon': 'Health & wellness',
    'plumber': 'Home & professional services',
    'electrician': 'Home & professional services',
    'carpenter': 'Home & professional services',
    'tailor': 'Retail & shopping',
    'general': 'Retail & shopping',
    'fashion': 'Retail & shopping',
    'electronics': 'Retail & shopping',
    'home_kitchen': 'Retail & shopping',
    'health_wellness': 'Health & wellness',
    'sports_fitness': 'Health & wellness',
    'automotive': 'Home & professional services',
    'books_stationery': 'Retail & shopping',
    'cleaning': 'Home & professional services',
    'hotel': 'Food & hospitality',
  };

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    final user = ref.read(authProvider).user;
    _ownerNameController.text = user?.displayName ?? '';
    _phoneController.text = user?.phoneE164 ?? '';
    _searchClaimController.addListener(_onSearchChanged);
    if (_mode == 1 && _searchClaimController.text.trim().length >= 2) {
      _loadClaimableListings(_searchClaimController.text);
    }
    if (_mode == 1) _loadMyClaimRequests();
  }

  Future<void> _loadMyClaimRequests() async {
    try {
      final response = await apiClient.get<Map<String, dynamic>>(
        '/merchant/business-claims',
      );
      final data = response.data?['data'];
      if (!mounted || data is! List) return;
      setState(
        () => _myClaimRequests = data
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
      );
    } catch (_) {
      // Search and submit remain usable; the pending-status area retries on next screen entry.
    }
  }

  void _switchToClaims() {
    setState(() => _mode = 1);
    _loadMyClaimRequests();
  }

  void _onSearchChanged() {
    _claimSearchDebounce?.cancel();
    final generation = ++_claimSearchGeneration;
    final query = _searchClaimController.text.trim();
    if (query.length < 2) {
      setState(() {
        _filteredClaimable = [];
        _claimSearchError = null;
        _claimSearchLoading = false;
      });
      return;
    }
    setState(() {
      _filteredClaimable = [];
      _claimSearchError = null;
      _claimSearchLoading = true;
    });
    _claimSearchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadClaimableListings(query, generation),
    );
  }

  Future<void> _loadClaimableListings(
    String query, [
    int? requestGeneration,
  ]) async {
    final generation = requestGeneration ?? _claimSearchGeneration;
    setState(() {
      _claimSearchLoading = true;
      _claimSearchError = null;
    });
    try {
      final response = await apiClient.get<Map<String, dynamic>>(
        '/merchant/claimable-businesses',
        queryParameters: {'query': query.trim()},
      );
      final data = response.data?['data'];
      if (data is! List)
        throw const FormatException('Invalid listing response');
      if (!mounted ||
          generation != _claimSearchGeneration ||
          query.trim() != _searchClaimController.text.trim())
        return;
      setState(() {
        _filteredClaimable = data
            .whereType<Map>()
            .map(_normalizeClaimableListing)
            .toList();
      });
    } catch (_) {
      if (!mounted || generation != _claimSearchGeneration) return;
      setState(() {
        _filteredClaimable = [];
        _claimSearchError =
            'Could not search listings. Check your connection and retry.';
      });
    } finally {
      if (mounted && generation == _claimSearchGeneration)
        setState(() => _claimSearchLoading = false);
    }
  }

  Map<String, dynamic> _normalizeClaimableListing(Map item) {
    String value(List<String> keys, String fallback) {
      for (final key in keys) {
        final candidate = item[key]?.toString().trim();
        if (candidate != null && candidate.isNotEmpty) return candidate;
      }
      return fallback;
    }

    return {
      'id': value(['id', 'business_id'], ''),
      'name': value(['name', 'business_name'], 'Business listing'),
      'category': value([
        'category',
        'category_name',
        'category_slug',
      ], 'Local business'),
      'locality': value(['locality', 'address'], 'Locality unavailable'),
      'city': value(['city'], 'Odisha'),
    };
  }

  Future<void> _showClaimConfirmationSheet(
    Map<String, dynamic> business,
  ) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _ClaimRequestSheet(
        businessName: business['name'] as String? ?? 'Business listing',
      ),
    );
    if (message == null || !mounted) return;
    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        '/merchant/businesses/${business['id']}/claim',
        data: {'message': message},
      );
      final data = response.data?['data'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(
        () => _filteredClaimable.removeWhere(
          (item) => item['id'] == business['id'],
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Claim request submitted. Reference ${data?['id'] ?? 'recorded'} · Pending admin review.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadMyClaimRequests();
    } on DioException catch (error) {
      if (!mounted) return;
      String? apiMessage;
      final responseData = error.response?.data;
      if (responseData is Map) {
        final errorData = responseData['error'];
        if (errorData is Map && errorData['message'] is String) {
          apiMessage = errorData['message'] as String;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiMessage ?? 'Could not submit the claim request. Please retry.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taxIdController.dispose();
    _taglineController.dispose();
    _addressController.dispose();
    _localityController.dispose();
    _cityController.dispose();
    _pinController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _searchClaimController.dispose();
    _claimSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _submitRegistration() async {
    if (!_resolveBusinessCoordinates() ||
        _selectedCategorySlug == null ||
        _businessNameController.text.trim().length < 2 ||
        _ownerNameController.text.trim().isEmpty ||
        _addressController.text.trim().length < 5 ||
        _localityController.text.trim().isEmpty ||
        !const [
          'cuttack',
          'jajpur',
        ].contains(_cityController.text.trim().toLowerCase()) ||
        !RegExp(r'^\d{6}$').hasMatch(_pinController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete the required business details, supported city and GPS location.',
          ),
        ),
      );
      setState(() => _currentStep = 2);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final phone = _phoneController.text.trim().isEmpty
          ? ref.read(authProvider).user!.phoneE164
          : _phoneController.text.trim();
      final contactPhone = phone.startsWith('+91') ? phone : '+91$phone';
      final response = await apiClient.post(
        '/merchant/businesses',
        data: {
          'name': _businessNameController.text.trim(),
          'description': _taglineController.text.trim(),
          'category_slug': _selectedCategorySlug,
          'phone_e164': contactPhone,
          'whatsapp_e164': contactPhone,
          'address_text': _addressController.text.trim(),
          'locality': _localityController.text.trim(),
          'city': _cityController.text.trim(),
          'postal_code': _pinController.text.trim(),
          'latitude': _businessLatitude,
          'longitude': _businessLongitude,
          if (_coverPhotoUrl != null) 'cover_photo_url': _coverPhotoUrl,
          'hours': List.generate(7, (weekday) {
            final isClosed =
                _hoursPreset == 'mon_sat' && weekday == DateTime.sunday % 7;
            final opensAt = _hoursPreset == 'all_days'
                ? '08:00'
                : (_hoursPreset == 'emergency' ? '00:00' : '09:00');
            final closesAt = _hoursPreset == 'all_days'
                ? '22:00'
                : (_hoursPreset == 'emergency' ? '23:59' : '20:30');
            return {
              'weekday': weekday,
              'is_closed': isClosed,
              'opens_at': isClosed ? null : opensAt,
              'closes_at': isClosed ? null : closesAt,
            };
          }),
        },
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final businessId = data['id'] as String;
      _generatedAppId = 'GN-${businessId.substring(0, 8).toUpperCase()}';
      await ref.read(authProvider.notifier).updateProfile({
        'display_name': _ownerNameController.text.trim(),
      });
      await ref.read(authProvider.notifier).setActiveRole('merchant');
      if (!mounted) return;
      setState(() => _isSuccess = true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not submit your business listing. ${_registrationError(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _registrationError(Object error) {
    if (error is DioException && error.response?.data is Map<String, dynamic>) {
      return (error.response!.data['error']?['message'] as String?) ??
          'Please review your details and try again.';
    }
    return 'Check your connection and try again.';
  }

  bool _resolveBusinessCoordinates() {
    if (_businessLatitude != null && _businessLongitude != null) return true;
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return false;
    }
    _businessLatitude = latitude;
    _businessLongitude = longitude;
    return true;
  }

  bool _validateCurrentStep() {
    if (_currentStep == 1) {
      if (_businessNameController.text.trim().length < 2 ||
          _ownerNameController.text.trim().isEmpty ||
          (_phoneController.text.trim().isNotEmpty &&
              !RegExp(r'^(\+91)?[6-9]\d{9}$')
                  .hasMatch(_phoneController.text.trim()))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a business name, owner name and valid contact number.',
            ),
          ),
        );
        return false;
      }
    }
    if (_currentStep == 2) {
      if (_addressController.text.trim().length < 5 ||
          _localityController.text.trim().isEmpty ||
          !const [
            'cuttack',
            'jajpur',
          ].contains(_cityController.text.trim().toLowerCase()) ||
          !RegExp(r'^\d{6}$').hasMatch(_pinController.text.trim()) ||
          !_resolveBusinessCoordinates()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a Cuttack or Jajpur address and capture its GPS location.',
            ),
          ),
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _captureBusinessLocation() async {
    setState(() => _isLocating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          'Allow location access to pin your business accurately.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _businessLatitude = position.latitude;
        _businessLongitude = position.longitude;
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message.toString()
                  : 'Could not get your location. Try again outdoors.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _chooseStorefrontPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null) return;
      setState(() => _isUploadingPhoto = true);
      final upload = await apiClient.uploadMedia(
        bytes: await image.readAsBytes(),
        filename: image.name,
        purpose: 'storefront',
      );
      if (!mounted) return;
      setState(() => _coverPhotoUrl = upload['url'] as String?);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storefront photo upload failed. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) {
      return _buildSuccessScreen();
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Merchant Onboarding'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.mainText,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildModeSegmentedControl(),
          ),
          Expanded(
            child: _mode == 0
                ? _buildRegisterWizard()
                : _buildClaimListingView(),
          ),
        ],
      ),
      bottomNavigationBar: _mode == 0 ? _buildWizardBottomBar() : null,
    );
  }

  // -------------------------------------------------------------
  // Mode Switcher (Register New vs Claim Existing)
  // -------------------------------------------------------------
  Widget _buildModeSegmentedControl() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _mode = 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _mode == 0 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _mode == 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_business_outlined,
                      size: 16,
                      color: _mode == 0
                          ? AppTheme.primary
                          : AppTheme.secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Register New',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _mode == 0
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _mode == 0
                            ? AppTheme.primary
                            : AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _switchToClaims,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _mode == 1 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _mode == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.store_mall_directory_outlined,
                      size: 16,
                      color: _mode == 1
                          ? AppTheme.primary
                          : AppTheme.secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Claim Existing',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _mode == 1
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _mode == 1
                            ? AppTheme.primary
                            : AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Register New Wizard
  // -------------------------------------------------------------
  Widget _buildRegisterWizard() {
    return SingleChildScrollView(
      key: const ValueKey('register_wizard'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step Stepper Indicator
          _buildStepProgressIndicator(),
          const SizedBox(height: 20),

          // Active Step View
          if (_currentStep == 0) _buildStepCategoryAndType(),
          if (_currentStep == 1) _buildStepBasicInfo(),
          if (_currentStep == 2) _buildStepLocationAndMedia(),
          if (_currentStep == 3) _buildStepOperationsAndReview(),

          const SizedBox(height: 80), // bottom bar padding
        ],
      ),
    );
  }

  Widget _buildStepProgressIndicator() {
    final steps = [
      'Type & Sector',
      'Basic Info',
      'Location & Store',
      'Operations',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: List.generate(steps.length, (idx) {
          final isDone = idx < _currentStep;
          final isCurrent = idx == _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? const Color(0xFF0F766E)
                              : (isCurrent
                                    ? AppTheme.primary
                                    : const Color(0xFFE2E8F0)),
                        ),
                        child: Center(
                          child: isDone
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isCurrent
                                        ? Colors.white
                                        : AppTheme.hintText,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        steps[idx],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isCurrent
                              ? AppTheme.primary
                              : AppTheme.secondaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (idx < steps.length - 1)
                  Container(
                    width: 16,
                    height: 2,
                    color: isDone
                        ? const Color(0xFF0F766E)
                        : const Color(0xFFE2E8F0),
                    margin: const EdgeInsets.only(bottom: 14),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // Step 1: Enterprise Type & Category
  Widget _buildStepCategoryAndType() {
    final categoryState = ref.watch(categoriesProvider);
    final categories = [...categoryState.items]
      ..sort((a, b) {
        const groupOrder = [
          'Retail & shopping',
          'Food & hospitality',
          'Health & wellness',
          'Home & professional services',
          'Other',
        ];
        final groupComparison = groupOrder
            .indexOf(_classificationBySlug[a.slug] ?? 'Other')
            .compareTo(
              groupOrder.indexOf(_classificationBySlug[b.slug] ?? 'Other'),
            );
        return groupComparison != 0
            ? groupComparison
            : a.name.compareTo(b.name);
      });
    final selectedCategory = categories
        .where((c) => c.slug == _selectedCategorySlug)
        .firstOrNull;
    if (selectedCategory != null) {
      _selectedCategoryName = selectedCategory.name;
    } else if (categories.isNotEmpty) {
      _selectedCategorySlug = categories.first.slug;
      _selectedCategoryName = categories.first.name;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Enterprise Classification',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.mainText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose the model that best describes how you conduct business.',
          style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 16),

        _buildEnterpriseTypeCard(
          typeId: 'retail',
          icon: Icons.storefront_outlined,
          title: 'Retail Shop & Showroom',
          subtitle:
              'Physical storefront with counter sales and customer walk-ins.',
          color: const Color(0xFF2457D6),
        ),
        const SizedBox(height: 12),
        _buildEnterpriseTypeCard(
          typeId: 'service_pro',
          icon: Icons.handyman_outlined,
          title: 'Skilled Trade & Professional',
          subtitle: 'Electrician, plumber, technician, or artisan offering on-site work.',
          color: const Color(0xFF0F766E),
        ),
        const SizedBox(height: 12),
        _buildEnterpriseTypeCard(
          typeId: 'food',
          icon: Icons.restaurant_outlined,
          title: 'Food, Dining & Cafe',
          subtitle: 'Dine-in restaurant, takeaway outlet, bakery, or cafe.',
          color: const Color(0xFFEA580C),
        ),
        const SizedBox(height: 12),
        _buildEnterpriseTypeCard(
          typeId: 'wellness',
          icon: Icons.spa_outlined,
          title: 'Salon, Spa & Wellness',
          subtitle: 'Appointment-based beauty salon, unisex parlour, or therapy studio.',
          color: const Color(0xFF7C3AED),
        ),

        const SizedBox(height: 24),
        const Text(
          'Primary business category',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.mainText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose the closest match. This helps customers find your listing.',
          style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 12),
        if (categoryState.isLoading && categories.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (categoryState.error != null && categories.isEmpty)
          _CategoryLoadError(
            onRetry: () => ref.read(categoriesProvider.notifier).load(),
          )
        else if (categories.isEmpty)
          const Text('No business categories are currently available.')
        else
          _CategoryPicker(
            categories: categories,
            selectedCategory: selectedCategory,
            classificationBySlug: _classificationBySlug,
            onSelected: (category) => setState(() {
              _selectedCategorySlug = category.slug;
              _selectedCategoryName = category.name;
            }),
          ),
      ],
    );
  }

  Widget _buildEnterpriseTypeCard({
    required String typeId,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final isSelected = _enterpriseType == typeId;

    return Material(
      color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('enterprise_type_$typeId'),
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            _enterpriseType = typeId;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : AppTheme.border,
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? color : AppTheme.mainText,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle, color: color, size: 20),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Step 2: Basic & Tax Info
  Widget _buildStepBasicInfo() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enterprise & Ownership Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.mainText,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Official details displayed to customers and verified on receipts.',
            style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 16),

          TextFormField(
            key: const ValueKey('merchant_business_name'),
            controller: _businessNameController,
            decoration: InputDecoration(
              labelText: 'Business / Trade Name *',
              hintText: 'e.g. Maa Tarini Hardware & Tools',
              prefixIcon: const Icon(Icons.business_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          TextFormField(
            key: const ValueKey('merchant_owner_name'),
            controller: _ownerNameController,
            decoration: InputDecoration(
              labelText: 'Owner / Authorized Person *',
              hintText: 'e.g. Srikant Mohanty',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('merchant_contact_phone'),
                  controller: _phoneController,
                  enabled: false,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Contact Phone *',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Support Email (Optional)',
              hintText: 'e.g. contact@business.com',
              prefixIcon: const Icon(Icons.alternate_email),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          TextFormField(
            key: const ValueKey('merchant_business_description'),
            controller: _taglineController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Short Description / Tagline',
              hintText: 'What products or services do you specialize in?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 18),

          // GST / PAN Section
          PremiumCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tax / Registration ID',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mainText,
                      ),
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: _isUnorganized,
                          onChanged: (v) =>
                              setState(() => _isUnorganized = v ?? false),
                          activeColor: AppTheme.primary,
                        ),
                        const Text(
                          'Local artisan / No GST',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!_isUnorganized) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _taxIdController,
                    decoration: InputDecoration(
                      labelText: 'GSTIN / Business PAN',
                      hintText: 'e.g. 21AAAAA0000A1Z5',
                      prefixIcon: const Icon(Icons.receipt_long_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Unregistered businesses and artisans can still list with Aadhaar or Electricity Bill proof.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Step 3: Location & Storefront Media
  Widget _buildStepLocationAndMedia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Storefront Location & Signage',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.mainText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Accurate location ensures nearby customers can find and visit your shop.',
          style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 16),

        TextFormField(
          key: const ValueKey('merchant_address'),
          controller: _addressController,
          decoration: InputDecoration(
            labelText: 'Street Address & Landmark *',
            hintText: 'e.g. Plot 42, Saheed Nagar Main Road',
            prefixIcon: const Icon(Icons.location_on_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('merchant_locality'),
                controller: _localityController,
                decoration: InputDecoration(
                  labelText: 'Locality *',
                  hintText: 'e.g. Saheed Nagar',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const ValueKey('merchant_city'),
                controller: _cityController,
                validator: (value) =>
                    const [
                      'cuttack',
                      'jajpur',
                    ].contains(value?.trim().toLowerCase())
                    ? null
                    : 'Choose Cuttack or Jajpur',
                decoration: InputDecoration(
                  labelText: 'City *',
                  hintText: 'Cuttack or Jajpur',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        TextFormField(
          key: const ValueKey('merchant_postal_code'),
          controller: _pinController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Postal PIN Code *',
            hintText: '751007',
            prefixIcon: const Icon(Icons.pin_drop_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 18),

        // Actual device location, captured only after merchant consent.
        PremiumCard(
          padding: const EdgeInsets.all(14),
          color: const Color(0xFFF0FDF4),
          borderColor: const Color(0xFFBBF7D0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.my_location,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _businessLatitude == null ||
                                  _businessLongitude == null
                              ? 'Business location not set'
                              : 'Business location set',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color:
                                _businessLatitude == null ||
                                    _businessLongitude == null
                                ? AppTheme.mainText
                                : Color(0xFF15803D),
                          ),
                        ),
                        Text(
                          _businessLatitude == null ||
                                  _businessLongitude == null
                              ? 'Use GPS or enter the storefront pin coordinates.'
                              : '${_businessLatitude!.toStringAsFixed(5)}, ${_businessLongitude!.toStringAsFixed(5)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('merchant_capture_location'),
                    onPressed: _isLocating ? null : _captureBusinessLocation,
                    icon: _isLocating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _businessLatitude == null ||
                                    _businessLongitude == null
                                ? Icons.my_location
                                : Icons.refresh,
                            size: 14,
                          ),
                    label: Text(
                      _businessLatitude == null || _businessLongitude == null
                          ? 'Locate'
                          : 'Update',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Enter map coordinates manually',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Use decimal latitude and longitude if GPS is unavailable.',
            style: TextStyle(fontSize: 12),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('merchant_latitude'),
                    controller: _latitudeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      hintText: '20.46575',
                    ),
                    onChanged: (_) => setState(() {
                      _businessLatitude = null;
                      _businessLongitude = null;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('merchant_longitude'),
                    controller: _longitudeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      hintText: '85.87900',
                    ),
                    onChanged: (_) => setState(() {
                      _businessLatitude = null;
                      _businessLongitude = null;
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Storefront photo is a real authenticated media upload.
        const Text(
          'Storefront Signage Photo',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.mainText,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey('storefront_photo_picker'),
          onTap: _isUploadingPhoto ? null : _chooseStorefrontPhoto,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _coverPhotoUrl != null
                    ? AppTheme.primary
                    : AppTheme.border,
                width: _coverPhotoUrl != null ? 1.5 : 1,
              ),
            ),
            child: _coverPhotoUrl != null
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.network(
                            apiClient.resolveMediaUrl(_coverPhotoUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.edit, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Change',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _isUploadingPhoto
                            ? const SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(),
                              )
                            : Icon(
                                Icons.add_a_photo_outlined,
                                size: 36,
                                color: AppTheme.primary,
                              ),
                        SizedBox(height: 8),
                        Text(
                          _isUploadingPhoto
                              ? 'Uploading photo…'
                              : 'Add a storefront photo',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.mainText,
                          ),
                        ),
                        Text(
                          'Choose a real photo from your gallery or camera',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.hintText,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // Step 4: Operations, Service Radius & Review
  Widget _buildStepOperationsAndReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operating Mode & Radius',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.mainText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Set how you service orders and define your service reach.',
          style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 16),

        // Operating Mode Selector
        Row(
          children: [
            _buildModePill('store_only', 'Walk-in Only', Icons.store),
            const SizedBox(width: 8),
            _buildModePill('home_only', 'On-site Visits', Icons.electric_bolt),
            const SizedBox(width: 8),
            _buildModePill('both', 'Store & On-site', Icons.alt_route),
          ],
        ),
        const SizedBox(height: 20),

        // Service Radius Slider
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Service & Delivery Coverage',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mainText,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_serviceRadiusKm.toInt()} km radius',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Customers within this perimeter will see your listing under "Nearby".',
                style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
              ),
              Slider(
                value: _serviceRadiusKm,
                min: 1.0,
                max: 20.0,
                divisions: 19,
                activeColor: AppTheme.primary,
                onChanged: (v) => setState(() => _serviceRadiusKm = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    '1 km (Neighbourhood)',
                    style: TextStyle(fontSize: 10, color: AppTheme.hintText),
                  ),
                  Text(
                    '20 km (City-wide)',
                    style: TextStyle(fontSize: 10, color: AppTheme.hintText),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Operating Hours Preset
        const Text(
          'Operating Schedule Preset',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.mainText,
          ),
        ),
        const SizedBox(height: 8),
        _buildHoursRadio(
          'mon_sat',
          'Mon - Sat (9:00 AM - 8:30 PM)',
          'Standard retail timing, Sunday closed',
        ),
        const SizedBox(height: 8),
        _buildHoursRadio(
          'all_days',
          'All 7 Days (8:00 AM - 10:00 PM)',
          'Open daily for retail & grocery walk-ins',
        ),
        const SizedBox(height: 8),
        _buildHoursRadio(
          'emergency',
          'Extended Daily Hours',
          'Open from 12:00 AM to 11:59 PM every day',
        ),

        const SizedBox(height: 20),

        // Application Summary Verification Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Application Summary',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mainText,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              _buildSummaryRow('Trade Name', _businessNameController.text),
              _buildSummaryRow('Sector', _selectedCategoryName),
              _buildSummaryRow(
                'Locality',
                '${_localityController.text}, ${_cityController.text}',
              ),
              _buildSummaryRow(
                'Coverage',
                '${_serviceRadiusKm.toInt()} km radius',
              ),
              _buildSummaryRow('Contact', _phoneController.text),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.mainText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModePill(String modeId, String label, IconData icon) {
    final isSelected = _operatingMode == modeId;
    return Expanded(
      child: GestureDetector(
        key: ValueKey('mode_pill_$modeId'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _operatingMode = modeId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppTheme.secondaryText,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppTheme.mainText,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHoursRadio(String val, String title, String subtitle) {
    final isSelected = _hoursPreset == val;
    return GestureDetector(
      key: ValueKey('hours_radio_$val'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _hoursPreset = val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppTheme.primary : AppTheme.hintText,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppTheme.primary : AppTheme.mainText,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.secondaryText,
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

  // Wizard Bottom Navigation Bar
  Widget _buildWizardBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => setState(() => _currentStep--),
                  child: const Text('Back'),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 5,
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSubmitting
                    ? null
                    : () {
                        if (_currentStep == 0 &&
                            _selectedCategoryName == 'Select a category') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Select a business category to continue.',
                              ),
                            ),
                          );
                        } else if (!_validateCurrentStep()) {
                          return;
                        } else if (_currentStep < 3) {
                          setState(() => _currentStep++);
                        } else {
                          _submitRegistration();
                        }
                      },
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _currentStep < 3
                            ? 'Save & Continue'
                            : 'Submit Application',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Claim Existing Listing View
  // -------------------------------------------------------------
  Widget _buildClaimListingView() {
    return SingleChildScrollView(
      key: const ValueKey('claim_listings'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Notice
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search approved business listings in Cuttack and Jajpur. You can request a review; ownership changes only after an administrator verifies the claim.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E3A8A),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_myClaimRequests.isNotEmpty) ...[
            const Text(
              'Your claim requests',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.mainText,
              ),
            ),
            const SizedBox(height: 8),
            ..._myClaimRequests.take(3).map((claim) {
              final status = claim['status'] as String? ?? 'pending';
              final approved = status == 'approved';
              final rejected = status == 'rejected';
              final color = approved
                  ? const Color(0xFF15803D)
                  : rejected
                  ? const Color(0xFFB42318)
                  : AppTheme.primary;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      approved
                          ? Icons.check_circle_outline
                          : rejected
                          ? Icons.info_outline
                          : Icons.hourglass_top_rounded,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            claim['business_name'] as String? ?? 'Business',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            rejected
                                ? 'Request declined · Contact support for details'
                                : approved
                                ? 'Ownership review approved'
                                : 'Waiting for administrator review',
                            style: TextStyle(color: color, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
          ],

          // Search Field
          TextField(
            controller: _searchClaimController,
            decoration: InputDecoration(
              hintText: 'Search name, category or locality...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Available listings for claim',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mainText,
                ),
              ),
              Text(
                _claimSearchLoading
                    ? 'Searching…'
                    : '${_filteredClaimable.length} found',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_claimSearchLoading && _filteredClaimable.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_claimSearchError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 42,
                      color: AppTheme.hintText,
                    ),
                    const SizedBox(height: 8),
                    Text(_claimSearchError!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () =>
                          _loadClaimableListings(_searchClaimController.text),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_searchClaimController.text.trim().length < 2)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 34),
                child: Text(
                  'Enter at least 2 characters to search approved listings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.secondaryText),
                ),
              ),
            )
          else if (_filteredClaimable.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const Icon(
                      Icons.search_off,
                      size: 48,
                      color: AppTheme.hintText,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No matching listing found',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Try a different business name, category or locality.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => setState(() => _mode = 0),
                      child: const Text('Register as New Business'),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final item in _filteredClaimable)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildClaimCard(item),
              ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildClaimCard(Map<String, dynamic> item) {
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.store,
                  color: AppTheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] as String,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mainText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item['category']} • ${item['locality']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Approved listing · ${item['city'] ?? 'Odisha'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.hintText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => _showClaimConfirmationSheet(item),
                  icon: const Icon(Icons.verified_outlined, size: 14),
                  label: const Text(
                    'Request review',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Success & Confirmation Screen
  // -------------------------------------------------------------
  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 30),
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFECFDF5),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 52,
                  color: Color(0xFF059669),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _mode == 0
                    ? 'Business Application Submitted'
                    : 'Claim request submitted',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Application Ref: $_generatedAppId',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 24),

              PremiumCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _buildSuccessRow(
                      Icons.business,
                      'Business',
                      _businessNameController.text,
                    ),
                    const Divider(height: 18),
                    _buildSuccessRow(
                      Icons.category_outlined,
                      'Category',
                      _selectedCategoryName,
                    ),
                    const Divider(height: 18),
                    _buildSuccessRow(
                      Icons.place_outlined,
                      'Location',
                      '${_localityController.text}, ${_cityController.text}',
                    ),
                    const Divider(height: 18),
                    _buildSuccessRow(
                      Icons.verified_outlined,
                      'Status',
                      'Pending verification',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.shield_outlined,
                      color: Color(0xFF16A34A),
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your listing is pending review. Prepare your products and services while it is reviewed; it will be published after approval.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF15803D),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MerchantWorkspaceScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text(
                    'Open Merchant Workspace',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.secondaryText),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const Spacer(),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.mainText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
