import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/screens/service_request_screen.dart';
import 'package:grepmind_mobile/core/screens/booking_scheduler_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen 13: Service Professional Profile
/// Matching Grepmind Near UI/UX Showcase Screen 13 & Service request.png.
class ServiceProScreen extends ConsumerStatefulWidget {
  final Business business;

  const ServiceProScreen({super.key, required this.business});

  @override
  ConsumerState<ServiceProScreen> createState() => _ServiceProScreenState();
}

class _ServiceProScreenState extends ConsumerState<ServiceProScreen> {
  bool _isSaved = false;
  List<Service> _services = [];
  bool _loadingServices = true;
  String? _selectedServiceId;

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  Future<void> _fetchServices() async {
    try {
      final res = await apiClient.get('/businesses/${widget.business.id}/services');
      final data = res.data as Map<String, dynamic>;
      final list = (data['data'] as List<dynamic>?)
              ?.map((e) => Service.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      if (mounted) {
        setState(() {
          _services = list;
          _loadingServices = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingServices = false);
      }
    }
  }

  void _callPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Calling $phone')),
        );
      }
    }
  }

  void _openWhatsApp(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening WhatsApp for $phone')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final biz = widget.business;
    final isVerified = biz.verificationStatus == 'verified';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Scrollable profile content
          CustomScrollView(
            slivers: [
              // Header Sliver
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    // Gradient Backdrop
                    Container(
                      height: 220,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF2457D6), Color(0xFF0F766E)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),

                    // Navigation Bar Actions
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.white.withValues(alpha: 0.9),
                              radius: 20,
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.mainText, size: 20),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                                  radius: 20,
                                  child: IconButton(
                                    icon: const Icon(Icons.share_outlined, color: AppTheme.mainText, size: 20),
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Professional profile link copied')),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                CircleAvatar(
                                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                                  radius: 20,
                                  child: IconButton(
                                    icon: Icon(
                                      _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                                      color: _isSaved ? AppTheme.primary : AppTheme.mainText,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() => _isSaved = !_isSaved);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(_isSaved ? 'Saved to bookmarks' : 'Removed from bookmarks'),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Profile Main Floating Card
                    Container(
                      margin: const EdgeInsets.only(top: 130, left: 16, right: 16),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Avatar
                              Stack(
                                children: [
                                  Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: const Color(0xFFDBEAFE), width: 2),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        biz.categorySlug == 'plumber'
                                            ? Icons.plumbing_rounded
                                            : Icons.engineering_rounded,
                                        size: 42,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check, color: Colors.white, size: 12),
                                    ),
                                  ),
                                ],
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
                                            biz.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.mainText,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                        ),
                                        if (isVerified) ...[
                                          const SizedBox(width: 4),
                                          const Icon(Icons.verified_rounded, color: AppTheme.primary, size: 18),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${biz.categoryName ?? 'Professional'} • 8+ Years Experience',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 18),
                                        const SizedBox(width: 4),
                                        const Text(
                                          '4.9',
                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          '(124 reviews)',
                                          style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Available Now',
                                            style: TextStyle(
                                              color: Color(0xFF15803D),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 12),
                          // Key Metrics Row (Screen 13 style)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildMetricItem(Icons.work_history_outlined, '8+ Years', 'Experience'),
                              _buildMetricDivider(),
                              _buildMetricItem(Icons.task_alt_rounded, '150+', 'Jobs Done'),
                              _buildMetricDivider(),
                              _buildMetricItem(Icons.verified_user_outlined, '100%', 'Vetted Pro'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Pro Details Body Content
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // About Section Card
                    _buildSectionCard(
                      title: 'About Professional',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            biz.description != null && biz.description!.isNotEmpty
                                ? biz.description!
                                : 'Experienced professional providing prompt, reliable, and guaranteed residential and commercial services. Background checked and equipped with modern tools.',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.secondaryText,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildBadge(Icons.shield_outlined, 'Background Verified'),
                              _buildBadge(Icons.timer_outlined, '15 min response time'),
                              _buildBadge(Icons.price_check_rounded, 'Upfront Pricing'),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Services & Rates Section Card
                    _buildSectionCard(
                      title: 'Services & Indicative Rates',
                      actionText: '${_services.length} available',
                      child: _loadingServices
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(color: AppTheme.primary),
                              ),
                            )
                          : _services.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text(
                                    'Standard consultation & visit charge: ₹199 - ₹499.',
                                    style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
                                  ),
                                )
                              : Column(
                                  children: _services.map((svc) {
                                    final isSelected = _selectedServiceId == svc.id;
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedServiceId = isSelected ? null : svc.id;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
                                            width: isSelected ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                              color: isSelected ? AppTheme.primary : const Color(0xFF94A3B8),
                                              size: 20,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    svc.name,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 14,
                                                      color: AppTheme.mainText,
                                                    ),
                                                  ),
                                                  if (svc.description != null && svc.description!.isNotEmpty) ...[
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      svc.description!,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: AppTheme.secondaryText,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              svc.priceText,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                                color: AppTheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                    ),

                    const SizedBox(height: 14),

                    // Service Area & Hours Card
                    _buildSectionCard(
                      title: 'Service Coverage & Availability',
                      child: Column(
                        children: [
                          _buildInfoRow(
                            Icons.location_on_outlined,
                            'Service Area',
                            'Within 10 km of ${biz.locality ?? biz.city ?? 'Bhubaneswar'}',
                          ),
                          const SizedBox(height: 10),
                          _buildInfoRow(
                            Icons.schedule_rounded,
                            'Working Hours',
                            'Mon - Sat: 8:00 AM - 8:00 PM (Emergency visits available)',
                          ),
                          const SizedBox(height: 10),
                          _buildInfoRow(
                            Icons.payments_outlined,
                            'Payment Methods',
                            'UPI, Cash, or Credit/Debit cards upon job completion',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Customer Reviews Card
                    _buildSectionCard(
                      title: 'Customer Reviews',
                      actionText: '124 reviews',
                      child: Column(
                        children: [
                          _buildReviewSnippet(
                            name: 'Subhashish Mohapatra',
                            rating: 5,
                            timeAgo: '2 days ago',
                            comment:
                                'Punctual and very neat wiring work. Identified the short circuit immediately and resolved it with minimal hassle!',
                          ),
                          const Divider(height: 18, color: Color(0xFFF1F5F9)),
                          _buildReviewSnippet(
                            name: 'Priyanka Dash',
                            rating: 5,
                            timeAgo: '1 week ago',
                            comment:
                                'Installed our 3 ceiling fans and living room chandelier perfectly. Cleaned up the debris after work. Highly recommend!',
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),

          // Sticky Bottom Actions Bar (Screen 13)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Call button
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.call_rounded, color: AppTheme.primary, size: 22),
                      onPressed: () => _callPhone(biz.phoneE164 ?? '+919876543220'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // WhatsApp button
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF15803D), size: 22),
                      onPressed: () => _openWhatsApp(biz.whatsappE164 ?? biz.phoneE164 ?? '+919876543220'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Custom Request button
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.edit_note_rounded, color: AppTheme.secondaryText, size: 24),
                      tooltip: 'Custom Request',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ServiceRequestScreen(
                              businessId: biz.id,
                              businessName: biz.name,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Primary Action CTA: Book / Schedule Slot
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          final selectedSvc = _services.where((s) => s.id == _selectedServiceId).firstOrNull;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BookingSchedulerScreen(
                                business: biz,
                                selectedService: selectedSvc,
                              ),
                            ),
                          );
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Book Appointment',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primary, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.mainText),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
        ),
      ],
    );
  }

  Widget _buildMetricDivider() {
    return Container(
      width: 1,
      height: 36,
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _buildBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mainText),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? actionText,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                  letterSpacing: -0.2,
                ),
              ),
              if (actionText != null)
                Text(
                  actionText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.secondaryText),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.mainText),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewSnippet({
    required String name,
    required int rating,
    required String timeAgo,
    required String comment,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.mainText),
            ),
            Text(
              timeAgo,
              style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(
            5,
            (index) => Icon(
              Icons.star_rounded,
              color: index < rating ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
              size: 15,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          comment,
          style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText, height: 1.35),
        ),
      ],
    );
  }
}
