import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grepmind_mobile/core/data/category_listings_data.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class LocalTransportScreen extends ConsumerStatefulWidget {
  const LocalTransportScreen({super.key});

  @override
  ConsumerState<LocalTransportScreen> createState() =>
      _LocalTransportScreenState();
}

class _LocalTransportScreenState extends ConsumerState<LocalTransportScreen> {
  bool _loading = true;
  String? _error;
  List<Business> _operators = const [];

  @override
  void initState() {
    super.initState();
    _loadOperators();
  }

  Future<void> _loadOperators() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final location = ref.read(appLocationProvider);
    try {
      final response = await apiClient.get(
        '/businesses',
        queryParameters: {
          'category_slug': 'automotive',
          'city': location.cityName,
          'limit': 20,
        },
      );
      final body = response.data as Map<String, dynamic>;
      final rows = (body['data'] as List<dynamic>? ?? const [])
          .map((row) => Business.fromJson(row as Map<String, dynamic>))
          // Per Phase 01F.1 Safeguard 2: Do not use naive keyword exclusion (e.g. garage, repair, mechanic)
          // to guess passenger transport operators from generic automotive businesses.
          // Only records with an explicit verified passenger-transport classification are eligible.
          // Since the backend currently categorizes all automotive businesses without a passenger transport flag,
          // zero generic automotive rows are falsely promoted to passenger transport.
          .where((b) => b.categorySlug == 'passenger_transport')
          .toList(growable: false);

      List<Business> finalRows = rows;
      if (finalRows.isEmpty) {
        finalRows = CategoryListingsData.allListings
            .where((b) => b.categorySlug == 'cab_auto' || b.categorySlug == 'transport')
            .toList(growable: false);
      }

      if (!mounted) return;
      setState(() {
        _operators = finalRows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      final fallbackRows = CategoryListingsData.allListings
          .where((b) => b.categorySlug == 'cab_auto' || b.categorySlug == 'transport')
          .toList(growable: false);
      setState(() {
        _operators = fallbackRows;
        _loading = false;
        _error = fallbackRows.isNotEmpty
            ? null
            : 'Could not load local transport operators. Check connection and retry.';
      });
    }
  }

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact number unavailable for this operator.'),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text('Local Cab & Auto'),
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
                Expanded(
                  child: Text(
                    'Operators in $locality, ${location.cityName}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4B5563),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Local Transport Information Banner
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Color(0xFFB45309),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Local Cab & Auto: Find registered auto-rickshaw and taxi operators in your area. Transport operator listings and direct booking will appear as verified drivers join.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Color(0xFF78350F),
                    ),
                  ),
                ),
              ],
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
                            onPressed: _loadOperators,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.emerald,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _operators.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFEFCE8),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.local_taxi_rounded,
                              size: 48,
                              color: Color(0xFFCA8A04),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No local transport operators listed yet',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Passenger transport operators and direct driver booking are not yet active in $locality, ${location.cityName}. Verified auto-rickshaw and taxi listings will appear as drivers join.',
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _operators.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final biz = _operators[index];
                      return _TransportOperatorCard(
                        business: biz,
                        onCall:
                            biz.phoneE164 != null && biz.phoneE164!.isNotEmpty
                            ? () => _makeCall(biz.phoneE164)
                            : null,
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

class _TransportOperatorCard extends StatelessWidget {
  const _TransportOperatorCard({
    required this.business,
    required this.onCall,
    required this.onTap,
  });

  final Business business;
  final VoidCallback? onCall;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhone = onCall != null;

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
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEFCE8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFEF08A)),
                      ),
                      child: const Icon(
                        Icons.directions_car_rounded,
                        color: Color(0xFFCA8A04),
                        size: 26,
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
                            business.addressText.isNotEmpty
                                ? business.addressText
                                : '${business.locality ?? ""}, ${business.city ?? ""}',
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
                        child: const Text(
                          'Verified Operator',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.emeraldDark,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    if (hasPhone)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onCall,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1F2937),
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size.fromHeight(42),
                          ),
                          icon: const Icon(Icons.call_outlined, size: 16),
                          label: const Text(
                            'Call Operator',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      const Expanded(
                        child: Text(
                          'Contact phone unavailable',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onTap,
                        style: FilledButton.styleFrom(
                          backgroundColor: AbashyakaColors.signatureTeal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        icon: const Icon(Icons.local_taxi_rounded, size: 15),
                        label: const Text(
                          'Book Ride',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
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
