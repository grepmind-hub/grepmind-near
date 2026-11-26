import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class DoctorDirectoryScreen extends ConsumerStatefulWidget {
  const DoctorDirectoryScreen({super.key});

  @override
  ConsumerState<DoctorDirectoryScreen> createState() =>
      _DoctorDirectoryScreenState();
}

class _DoctorDirectoryScreenState extends ConsumerState<DoctorDirectoryScreen> {
  bool _loading = true;
  String? _error;
  List<Business> _facilities = const [];

  @override
  void initState() {
    super.initState();
    _loadClinics();
  }

  Future<void> _loadClinics() async {
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
        _facilities = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load clinics and medical facilities. Check connection and retry.';
        _loading = false;
      });
    }
  }

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact number unavailable for this facility.'),
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
      backgroundColor: context.abashyaka.canvas,
      appBar: AppBar(
        title: const Text('Clinics & Medical Facilities'),
        backgroundColor: context.abashyaka.card,
        foregroundColor: context.abashyaka.textPrimary,
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
            color: context.abashyaka.card,
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
                    'Clinics & Facilities near $locality, ${location.cityName}',
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

          // Information / Verification Notice Card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCFCE7)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.emerald,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Doctor consultation schedules are not available in this area yet. Contact registered clinics directly for specialist visiting hours.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF166534),
                      height: 1.35,
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
                            onPressed: _loadClinics,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.emerald,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _facilities.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF0F9FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.medical_services_outlined,
                              size: 48,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No clinics or medical facilities listed yet',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Registered clinics and healthcare centres near $locality will appear here as they join.',
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: _facilities.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final biz = _facilities[index];
                      return _MedicalFacilityCard(
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

class _MedicalFacilityCard extends StatelessWidget {
  const _MedicalFacilityCard({
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
        color: context.abashyaka.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.abashyaka.border),
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
                // Top row: Facility icon and name
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC8E6C9)),
                      ),
                      child: const Icon(
                        Icons.local_hospital_outlined,
                        color: Color(0xFF0B6B4A),
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
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            business.categoryName ??
                                'Medical Facility & Clinic',
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
                          'Facility Verified',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.emeraldDark,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Location & operating status
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              business.addressText.isNotEmpty
                                  ? business.addressText
                                  : '${business.locality ?? ""}, ${business.city ?? ""}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 15,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              business.isOpenNow
                                  ? 'Facility open now'
                                  : 'Facility closed · Check regular hours',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: business.isOpenNow
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF4B5563),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Actions: Call facility or details
                Row(
                  children: [
                    if (hasPhone)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onCall,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1F2937),
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size.fromHeight(42),
                          ),
                          icon: const Icon(Icons.call_outlined, size: 16),
                          label: const Text(
                            'Call Clinic',
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
                          'Contact phone not listed',
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
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        icon: const Icon(Icons.storefront_outlined, size: 15),
                        label: const Text(
                          'View Details',
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
