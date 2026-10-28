import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/models/business.dart';

/// Screen 18: Service Request Status Tracker
/// Authoritative reference: Grepmind Near UI/UX Showcase Screen 18 & ref-image/Service request.png
class ServiceRequestStatusScreen extends ConsumerStatefulWidget {
  final ServiceRequest? request;
  final Business? business;
  final String? requestId;
  final String? businessName;
  final String? serviceName;
  final DateTime? appointmentTime;
  final String? initialStatus;

  const ServiceRequestStatusScreen({
    super.key,
    this.request,
    this.business,
    this.requestId,
    this.businessName,
    this.serviceName,
    this.appointmentTime,
    this.initialStatus,
  });

  @override
  ConsumerState<ServiceRequestStatusScreen> createState() => _ServiceRequestStatusScreenState();
}

class _ServiceRequestStatusScreenState extends ConsumerState<ServiceRequestStatusScreen> {
  late String _currentStatus;
  late final String _bookingId;
  late final DateTime _scheduledTime;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.initialStatus ?? widget.request?.status ?? 'requested';
    _bookingId = widget.requestId ??
        (widget.request?.id != null
            ? '#GN-${widget.request!.id.substring(0, 4).toUpperCase()}'
            : '#GN-4921');
    _scheduledTime = widget.appointmentTime ??
        widget.request?.requestedFor ??
        DateTime.now().add(const Duration(hours: 2));
  }

  String get _providerName {
    if (widget.business?.name != null && widget.business!.name.isNotEmpty) {
      return widget.business!.name;
    }
    if (widget.businessName != null && widget.businessName!.isNotEmpty) {
      return widget.businessName!;
    }
    return 'Ramesh Kumar - Electrical Services';
  }

  String get _providerShortName {
    final parts = _providerName.split(' ');
    return parts.isNotEmpty ? parts.first : 'Provider';
  }

  String get _serviceTitle {
    if (widget.serviceName != null && widget.serviceName!.isNotEmpty) {
      return widget.serviceName!;
    }
    if (widget.request?.description != null && widget.request!.description.isNotEmpty) {
      return widget.request!.description;
    }
    return 'Ceiling Fan & Light Fixture Install';
  }

  Future<void> _makePhoneCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calling $phone...')),
      );
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=Hi%20$_providerShortName,%20regarding%20my%20service%20request%20$_bookingId');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opening WhatsApp for $cleanPhone...')),
      );
    }
  }

  void _showCancelConfirmationModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cancel Service Request?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.mainText,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'You will not be charged any cancellation fee.',
                        style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Please tell us the reason:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mainText),
            ),
            const SizedBox(height: 10),
            ...[
              'Found another skilled professional',
              'Scheduled for the wrong date / time',
              'Problem resolved by myself',
              'Cost estimate higher than expected',
            ].map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    setState(() => _currentStatus = 'cancelled');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Request $_bookingId cancelled')),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      reason,
                      style: const TextStyle(fontSize: 13, color: AppTheme.mainText, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Keep My Request', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.mainText)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupportModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Grepmind Help & Support',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.mainText),
            ),
            const SizedBox(height: 6),
            const Text(
              'Need assistance with your booking or provider communication?',
              style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 18),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.headset_mic_rounded, color: AppTheme.primary),
              ),
              title: const Text('Call Customer Support', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('Toll-free • Available 8 AM - 10 PM', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () {
                Navigator.of(ctx).pop();
                _makePhoneCall('1800123456');
              },
            ),
            const Divider(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.chat_outlined, color: Color(0xFF15803D)),
              ),
              title: const Text('Live Chat via WhatsApp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('Instant support bot & support agent', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () {
                Navigator.of(ctx).pop();
                _openWhatsApp('+919876543210');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppTheme.mainText),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Service Request Status',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.mainText,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Booking ID $_bookingId',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.secondaryText,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: AppTheme.mainText),
            tooltip: 'Help & Support',
            onPressed: _showSupportModal,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppTheme.mainText),
            tooltip: 'Share Details',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Shared status link for $_bookingId')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                children: [
                  // Hero Status Card with pulsing pill
                  _buildHeroLiveStatusCard(),
                  const SizedBox(height: 14),

                  // Demo Stage Switcher (Allows testing each stage of the request live)
                  _buildStageSwitcherBar(),
                  const SizedBox(height: 16),

                  // Multi-Step Progress Tracker Timeline
                  _buildTimelineStepperCard(),
                  const SizedBox(height: 16),

                  // Assigned Professional Card
                  _buildAssignedProfessionalCard(),
                  const SizedBox(height: 16),

                  // Job & Booking Summary Receipt
                  _buildReceiptSummaryCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // Bottom Sticky Actions Bar
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroLiveStatusCard() {
    Color bgGradientStart;
    Color bgGradientEnd;
    Color pillColor;
    Color pillTextColor;
    String statusTitle;
    String statusDescription;
    IconData statusIcon;

    switch (_currentStatus) {
      case 'accepted':
        bgGradientStart = const Color(0xFF1E3A8A);
        bgGradientEnd = const Color(0xFF2457D6);
        pillColor = const Color(0xFFEFF6FF);
        pillTextColor = AppTheme.primary;
        statusTitle = 'Accepted by Pro';
        statusDescription = '$_providerShortName accepted your request. Expected arrival on schedule.';
        statusIcon = Icons.thumb_up_alt_rounded;
        break;
      case 'en_route':
        bgGradientStart = const Color(0xFF0F766E);
        bgGradientEnd = const Color(0xFF14B8A6);
        pillColor = const Color(0xFFCCFBF1);
        pillTextColor = const Color(0xFF0F766E);
        statusTitle = 'Professional En Route';
        statusDescription = '$_providerShortName is heading to your address. ETA approx 18 mins.';
        statusIcon = Icons.navigation_rounded;
        break;
      case 'in_progress':
        bgGradientStart = const Color(0xFF7C2D12);
        bgGradientEnd = const Color(0xFFEA580C);
        pillColor = const Color(0xFFFFEDD5);
        pillTextColor = const Color(0xFFC2410C);
        statusTitle = 'Job In Progress';
        statusDescription = '$_providerShortName is actively working on your electrical repair.';
        statusIcon = Icons.build_circle_rounded;
        break;
      case 'completed':
        bgGradientStart = const Color(0xFF064E3B);
        bgGradientEnd = const Color(0xFF059669);
        pillColor = const Color(0xFFECFDF5);
        pillTextColor = const Color(0xFF047857);
        statusTitle = 'Job Completed';
        statusDescription = 'The service has been completed successfully. Please review & pay.';
        statusIcon = Icons.task_alt_rounded;
        break;
      case 'cancelled':
        bgGradientStart = const Color(0xFF7F1D1D);
        bgGradientEnd = const Color(0xFFDC2626);
        pillColor = const Color(0xFFFEF2F2);
        pillTextColor = const Color(0xFFDC2626);
        statusTitle = 'Request Cancelled';
        statusDescription = 'This service request was cancelled. No charges applied.';
        statusIcon = Icons.cancel_outlined;
        break;
      case 'requested':
      default:
        bgGradientStart = const Color(0xFF1E293B);
        bgGradientEnd = const Color(0xFF334155);
        pillColor = const Color(0xFFF1F5F9);
        pillTextColor = const Color(0xFF1E293B);
        statusTitle = 'Request Submitted';
        statusDescription = 'Awaiting confirmation from $_providerShortName within 15 minutes.';
        statusIcon = Icons.hourglass_top_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bgGradientStart, bgGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: bgGradientEnd.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: pillTextColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _currentStatus.toUpperCase().replaceAll('_', ' '),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: pillTextColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(statusIcon, color: Colors.white.withValues(alpha: 0.9), size: 28),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            statusTitle,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            statusDescription,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageSwitcherBar() {
    final stages = [
      {'key': 'requested', 'label': 'Requested'},
      {'key': 'accepted', 'label': 'Accepted'},
      {'key': 'en_route', 'label': 'En Route'},
      {'key': 'in_progress', 'label': 'Progress'},
      {'key': 'completed', 'label': 'Done'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: stages.map((stage) {
            final isSelected = _currentStatus == stage['key'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _currentStatus = stage['key']!),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    stage['label']!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.secondaryText,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTimelineStepperCard() {
    final steps = [
      {
        'title': 'Request Submitted',
        'subtitle': 'Details sent to $_providerShortName',
        'time': '10:30 AM',
        'state': _getStepState('requested'),
      },
      {
        'title': 'Provider Accepted',
        'subtitle': '$_providerShortName accepted the booking',
        'time': _currentStatus != 'requested' ? '10:38 AM' : '--:--',
        'state': _getStepState('accepted'),
      },
      {
        'title': 'Professional En Route',
        'subtitle': 'Traveling to Saheed Nagar location',
        'time': (_currentStatus == 'en_route' || _currentStatus == 'in_progress' || _currentStatus == 'completed')
            ? '11:15 AM'
            : '--:--',
        'state': _getStepState('en_route'),
      },
      {
        'title': 'Job In Progress',
        'subtitle': 'Inspection and fixtures installation',
        'time': (_currentStatus == 'in_progress' || _currentStatus == 'completed') ? '11:35 AM' : '--:--',
        'state': _getStepState('in_progress'),
      },
      {
        'title': 'Job Completed & Verified',
        'subtitle': 'Final test & payment receipt generated',
        'time': _currentStatus == 'completed' ? '12:20 PM' : '--:--',
        'state': _getStepState('completed'),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Live Progress Timeline',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.mainText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, size: 12, color: Color(0xFF059669)),
                    SizedBox(width: 4),
                    Text(
                      'Live Tracking',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...List.generate(steps.length, (index) {
            final isLast = index == steps.length - 1;
            final step = steps[index];
            final stepState = step['state'] as String; // 'done', 'current', 'upcoming'

            return _buildTimelineStepRow(
              title: step['title'] as String,
              subtitle: step['subtitle'] as String,
              time: step['time'] as String,
              state: stepState,
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }

  String _getStepState(String stepKey) {
    if (_currentStatus == 'cancelled') return 'upcoming';

    final order = ['requested', 'accepted', 'en_route', 'in_progress', 'completed'];
    final currentIndex = order.indexOf(_currentStatus);
    final stepIndex = order.indexOf(stepKey);

    if (stepIndex < currentIndex) return 'done';
    if (stepIndex == currentIndex) return 'current';
    return 'upcoming';
  }

  Widget _buildTimelineStepRow({
    required String title,
    required String subtitle,
    required String time,
    required String state,
    required bool isLast,
  }) {
    Color circleColor;
    Widget iconWidget;

    if (state == 'done') {
      circleColor = const Color(0xFF059669);
      iconWidget = const Icon(Icons.check_rounded, color: Colors.white, size: 14);
    } else if (state == 'current') {
      circleColor = AppTheme.primary;
      iconWidget = Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      );
    } else {
      circleColor = const Color(0xFFCBD5E1);
      iconWidget = Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step Icon & Vertical Line
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: circleColor,
                  shape: BoxShape.circle,
                  boxShadow: state == 'current'
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: iconWidget,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: state == 'done' ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),

          // Step Text & Time
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: state == 'current' ? FontWeight.w800 : FontWeight.w600,
                            color: state == 'upcoming' ? AppTheme.secondaryText : AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 2),
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
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: state == 'upcoming' ? const Color(0xFF94A3B8) : AppTheme.secondaryText,
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

  Widget _buildAssignedProfessionalCard() {
    final pro = widget.business;
    final rating = pro?.rating ?? 4.9;
    final phone = pro?.phoneE164 ?? '+919876543220';
    final whatsapp = pro?.whatsappE164 ?? phone;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Assigned Professional',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.mainText),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Pro Avatar
              Stack(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2457D6), Color(0xFF0F766E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _providerShortName.isNotEmpty ? _providerShortName[0] : 'P',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Color(0xFF2457D6), shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Name & Rating
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _providerName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.mainText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF2457D6)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          '$rating (124+ completed)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mainText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Saheed Nagar, Bhubaneswar • 1.8 km',
                      style: TextStyle(fontSize: 11, color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Contact Actions: Direct Call & WhatsApp
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                      backgroundColor: const Color(0xFFEFF6FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.call_rounded, size: 16),
                    label: const Text('Call Pro', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    onPressed: () => _makePhoneCall(phone),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF15803D),
                      side: const BorderSide(color: Color(0xFFBBF7D0)),
                      backgroundColor: const Color(0xFFDCFCE7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    onPressed: () => _openWhatsApp(whatsapp),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptSummaryCard() {
    final dateFormat = DateFormat('EEE, MMM d, yyyy • hh:mm a');
    final formattedDate = dateFormat.format(_scheduledTime);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Job & Receipt Summary',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.mainText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _bookingId,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _buildReceiptRow('Service Requested', _serviceTitle, isBold: true),
          const SizedBox(height: 10),
          _buildReceiptRow('Appointment Slot', formattedDate),
          const SizedBox(height: 10),
          _buildReceiptRow('Address', 'Plot 42, Saheed Nagar, Bhubaneswar'),
          const SizedBox(height: 10),
          _buildReceiptRow('Indicative Estimate', '₹299 - ₹599', isHighlight: true),
          const SizedBox(height: 10),
          _buildReceiptRow('Payment Mode', 'Pay after job (Cash / UPI / Card)'),

          if (widget.request?.description != null && widget.request!.description.isNotEmpty) ...[
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            const Text(
              'Customer Instructions:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 4),
            Text(
              widget.request!.description,
              style: const TextStyle(fontSize: 12, color: AppTheme.mainText, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isBold = false, bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: isHighlight ? AppTheme.primary : AppTheme.mainText,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
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
          if (_currentStatus != 'completed' && _currentStatus != 'cancelled') ...[
            // Cancel Request Action Button
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    backgroundColor: const Color(0xFFFEF2F2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _showCancelConfirmationModal,
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Primary Navigation or Done Button
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.home_outlined, color: Colors.white, size: 18),
                label: Text(
                  _currentStatus == 'completed' ? 'Back to Home' : 'Back to Explore',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                ),
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
