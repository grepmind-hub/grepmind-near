import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/service_request_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class PharmacyMarketplaceScreen extends ConsumerStatefulWidget {
  const PharmacyMarketplaceScreen({super.key});

  @override
  ConsumerState<PharmacyMarketplaceScreen> createState() =>
      _PharmacyMarketplaceScreenState();
}

class _PharmacyMarketplaceScreenState
    extends ConsumerState<PharmacyMarketplaceScreen> {
  String _selectedFilter = 'All';
  bool _loading = true;
  String? _error;
  List<Business> _pharmacies = const [];

  static const _filters = [
    'All',
    'Open Now',
    'Home Delivery',
    '24x7 Emergency',
    'Ayurvedic & OTC',
  ];

  @override
  void initState() {
    super.initState();
    _loadPharmacies();
  }

  Future<void> _loadPharmacies() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final location = ref.read(appLocationProvider);
    try {
      final response = await apiClient.get(
        '/businesses',
        queryParameters: {
          'category_slug': 'medical',
          'city': location.cityName,
          'limit': 20,
        },
      );
      final body = response.data as Map<String, dynamic>;
      final rows = (body['data'] as List<dynamic>? ?? const [])
          .map((row) => Business.fromJson(row as Map<String, dynamic>))
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _pharmacies = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load pharmacies. Check your connection and retry.';
        _loading = false;
      });
    }
  }

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact number unavailable for this pharmacy.'),
        ),
      );
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open phone dialer for $phone')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(appLocationProvider);
    final locality = location.localityName.isNotEmpty
        ? location.localityName
        : (location.cityName == 'Cuttack' ? 'Kuanpal' : 'Chhatia');

    final filtered = _pharmacies
        .where((p) {
          if (_selectedFilter == 'Open Now') return p.isOpenNow;
          return true;
        })
        .toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text('Medicines & Pharmacy'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Subheader context
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: AppTheme.emerald,
                ),
                const SizedBox(width: 4),
                Text(
                  'Pharmacies near $locality, ${location.cityName}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Prescription Order / Chemist Inquiry Banner Card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC8E6C9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: AppTheme.emerald,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Prescription Medicines & Inquiries',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF064D3A),
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'For scheduled prescription medicines, please call or visit your local chemist directly with a valid prescription.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF2E7D32),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_pharmacies.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => _makeCall(_pharmacies.first.phoneE164),
                      icon: const Icon(Icons.call_rounded, size: 14),
                      label: const Text('Call Pharmacy'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF064D3A),
                        side: const BorderSide(color: Color(0xFF0B6B4A)),
                        backgroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Filter Chips
          Container(
            height: 48,
            color: Colors.transparent,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  selectedColor: const Color(0xFFE8F5E9),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: isSelected
                        ? AppTheme.emerald
                        : const Color(0xFFE5E7EB),
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.emeraldDark
                        : const Color(0xFF374151),
                  ),
                  showCheckmark: false,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedFilter = filter);
                  },
                );
              },
            ),
          ),

          // Main Listing Content
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.emerald),
                  )
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            size: 48,
                            color: Color(0xFF9CA3AF),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF4B5563)),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loadPharmacies,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.emerald,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFF1F2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.medication_rounded,
                              size: 48,
                              color: Color(0xFFE11D48),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No pharmacies found',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Medical stores and pharmacies near $locality will appear here as they register.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final biz = filtered[index];
                      return _PharmacyStoreCard(
                        business: biz,
                        onCall: () => _makeCall(biz.phoneE164),
                        onInquire: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ServiceRequestScreen(
                              businessId: biz.id,
                              businessName: biz.name,
                            ),
                          ),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                BusinessDetailScreen(businessId: biz.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PharmacyStoreCard extends StatelessWidget {
  const _PharmacyStoreCard({
    required this.business,
    required this.onCall,
    required this.onInquire,
    required this.onTap,
  });

  final Business business;
  final VoidCallback onCall;
  final VoidCallback onInquire;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1EBE5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBF0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFCDD2)),
                      ),
                      child: const Icon(
                        Icons.local_pharmacy_rounded,
                        color: Color(0xFFE11D48),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            business.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Chemist & Druggist · ${business.locality ?? business.city ?? 'Local'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (business.verificationStatus == 'verified')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 13,
                              color: AppTheme.emerald,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Verified Listing',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.emeraldDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF3F4F6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          business.isOpenNow
                              ? 'Store open now'
                              : 'Closed currently',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: business.isOpenNow
                                ? const Color(0xFF059669)
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Dual Action Buttons (Contact / Inquire)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onCall,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1F2937),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size.fromHeight(40),
                        ),
                        icon: const Icon(Icons.call_outlined, size: 16),
                        label: const Text(
                          'Call Store',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size.fromHeight(40),
                        ),
                        icon: const Icon(Icons.storefront_outlined, size: 16),
                        label: const Text(
                          'View Store',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
