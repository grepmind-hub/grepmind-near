import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/widgets/abashyaka_premium_header.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_painter.dart';
import 'package:grepmind_mobile/core/widgets/metallic_button.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

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
  ConsumerState<ServiceRequestStatusScreen> createState() =>
      _ServiceRequestStatusScreenState();
}

class _ServiceRequestStatusScreenState
    extends ConsumerState<ServiceRequestStatusScreen> {
  late String _currentStatus;
  late final String _bookingId;
  DateTime? _scheduledTime;
  bool _isConfirmingReschedule = false;

  Timer? _statusPollTimer;

  @override
  void initState() {
    super.initState();
    _currentStatus =
        widget.initialStatus ?? widget.request?.status ?? 'requested';
    final requestID = widget.requestId ?? widget.request?.id;
    _bookingId = requestID ?? 'Unavailable';
    _scheduledTime = widget.appointmentTime ?? widget.request?.requestedFor;

    _fetchLiveStatus();
    _startLiveTracking();
  }

  void _startLiveTracking() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      _fetchLiveStatus();
    });
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLiveStatus() async {
    if (widget.requestId == null || widget.requestId!.isEmpty) return;
    try {
      final res = await apiClient.get('/requests/${widget.requestId}');
      final data = res.data as Map<String, dynamic>;
      final reqData = data['data'] as Map<String, dynamic>?;
      if (reqData != null && reqData['status'] != null) {
        if (mounted) {
          final newStatus = reqData['status'] as String;
          final rawRequestedFor = reqData['requested_for'] as String?;
          final parsedRequestedFor = rawRequestedFor == null
              ? null
              : DateTime.tryParse(rawRequestedFor)?.toLocal();
          if (_currentStatus != newStatus ||
              (parsedRequestedFor != null &&
                  parsedRequestedFor != _scheduledTime)) {
            setState(() {
              _currentStatus = newStatus;
              if (parsedRequestedFor != null) {
                _scheduledTime = parsedRequestedFor;
              }
            });
          }
          if (newStatus == 'completed' ||
              newStatus == 'cancelled' ||
              newStatus == 'declined') {
            _statusPollTimer?.cancel();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _confirmProposedTime() async {
    final requestId = widget.requestId ?? widget.request?.id;
    if (requestId == null || requestId.isEmpty || _isConfirmingReschedule) {
      return;
    }
    setState(() => _isConfirmingReschedule = true);
    try {
      await apiClient.post('/requests/$requestId/confirm-reschedule');
      if (!mounted) return;
      setState(() => _currentStatus = 'accepted');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The new appointment time is confirmed.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not confirm the new time. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirmingReschedule = false);
    }
  }

  String get _providerName {
    if (widget.business?.name != null && widget.business!.name.isNotEmpty) {
      return widget.business!.name;
    }
    if (widget.businessName != null && widget.businessName!.isNotEmpty) {
      return widget.businessName!;
    }
    return 'Provider details unavailable';
  }

  String get _providerShortName {
    final parts = _providerName.split(' ');
    return parts.isNotEmpty ? parts.first : 'Provider';
  }

  String get _serviceTitle {
    if (widget.serviceName != null && widget.serviceName!.isNotEmpty) {
      return widget.serviceName!;
    }
    if (widget.request?.description != null &&
        widget.request!.description.isNotEmpty) {
      return widget.request!.description;
    }
    return 'Service details unavailable';
  }

  Future<void> _makePhoneCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Calling $phone...')));
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse(
      'https://wa.me/$cleanPhone?text=Hi%20$_providerShortName,%20regarding%20my%20service%20request%20$_bookingId',
    );
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
      backgroundColor: AbashyakaColors.pureWhite,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AbashyakaSpacing.lg,
            0,
            AbashyakaSpacing.lg,
            AbashyakaSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.error,
                      size: 24,
                    ),
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
                          'Choose a reason to cancel this request.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Please tell us the reason:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mainText,
                ),
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
                    onTap: () async {
                      if (widget.requestId == null) return;
                      try {
                        await apiClient.post(
                          '/requests/${widget.requestId}/cancel',
                        );
                        if (!mounted || !ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        setState(() => _currentStatus = 'cancelled');
                      } catch (_) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('This request cannot be cancelled.'),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(
                        minHeight: AbashyakaSpacing.touchTargetMin,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        reason,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.mainText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AbashyakaSpacing.touchTargetMin),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: AppTheme.border),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Keep My Request',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mainText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSupportModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AbashyakaColors.pureWhite,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AbashyakaSpacing.lg,
            0,
            AbashyakaSpacing.lg,
            AbashyakaSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Abashyaka Help & Support',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                ),
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
                  decoration: BoxDecoration(
                    color: AppTheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.headset_mic_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                title: const Text(
                  'Call Customer Support',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: const Text(
                  'Support contact is not configured.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              ),
              const Divider(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.chat_outlined,
                    color: AppTheme.deepEmerald,
                  ),
                ),
                title: const Text(
                  'Live Chat via WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: const Text(
                  'Support chat is not configured.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _stages = <(String, String)>[
    ('requested', 'Request Submitted'),
    ('accepted', 'Provider Accepted'),
    ('en_route', 'Professional En Route'),
    ('in_progress', 'Job In Progress'),
    ('completed', 'Job Completed'),
  ];

  @override
  Widget build(BuildContext context) {
    final status = _statusPresentation();
    final scale = MediaQuery.textScalerOf(context).scale(16);
    final fixedActions =
        MediaQuery.sizeOf(context).height >= 480 && scale <= 24;
    final actions = _buildBottomActions(context, scale);

    return Scaffold(
      backgroundColor: AbashyakaColors.pearlWhite,
      appBar: AppBar(
        backgroundColor: AbashyakaColors.pearlWhite,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: const Text('Service Request Status', maxLines: 2),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Help & Support',
            onPressed: _showSupportModal,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share Details',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Shared status link for $_bookingId')),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: fixedActions ? actions : null,
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            AbashyakaPremiumHeader(
              variant: FluidWaveVariant.tracking,
              bottom: _buildStatusCard(status),
            ),
            Padding(
              padding: const EdgeInsets.all(AbashyakaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTimeline(status),
                  const SizedBox(height: AbashyakaSpacing.md),
                  _buildProfessionalCard(),
                  const SizedBox(height: AbashyakaSpacing.md),
                  _buildReceipt(),
                ],
              ),
            ),
            if (!fixedActions) actions,
          ],
        ),
      ),
    );
  }

  ({String title, String description, IconData icon, Color color})
  _statusPresentation() {
    final (title, description, icon, color) = switch (_currentStatus) {
      'requested' => (
        'Request Submitted',
        'Waiting for the provider to respond.',
        Icons.hourglass_top_rounded,
        AbashyakaColors.signatureTeal,
      ),
      'accepted' => (
        'Accepted by Pro',
        'The provider accepted your request.',
        Icons.event_available_outlined,
        AbashyakaColors.signatureTeal,
      ),
      'rescheduled' => (
        'New Time Proposed',
        'Review the proposed appointment time and confirm it below.',
        Icons.event_repeat_rounded,
        AbashyakaColors.ratingText,
      ),
      'en_route' => (
        'Professional En Route',
        'The provider is on the way.',
        Icons.navigation_outlined,
        AbashyakaColors.signatureTeal,
      ),
      'in_progress' => (
        'Job In Progress',
        'The provider has started the service.',
        Icons.build_outlined,
        AbashyakaColors.signatureTeal,
      ),
      'completed' => (
        'Job Completed',
        'The provider marked the service complete.',
        Icons.task_alt_rounded,
        AbashyakaColors.signatureTeal,
      ),
      'declined' => (
        'Request Declined',
        'The provider declined this request.',
        Icons.block_outlined,
        AbashyakaColors.error,
      ),
      'cancelled' => (
        'Request Cancelled',
        'This service request was cancelled.',
        Icons.cancel_outlined,
        AbashyakaColors.error,
      ),
      _ => (
        'Status Unavailable',
        'The current status could not be displayed.',
        Icons.info_outline,
        AbashyakaColors.graphiteCharcoal,
      ),
    };

    return (title: title, description: description, icon: icon, color: color);
  }

  Widget _buildStatusCard(
    ({String title, String description, IconData icon, Color color}) status,
  ) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconTile(status.icon, status.color),
              const SizedBox(width: AbashyakaSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    status.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AbashyakaColors.premiumObsidian,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AbashyakaSpacing.sm),
          Text(
            status.description,
            style: const TextStyle(color: AbashyakaColors.graphiteCharcoal),
          ),
          if (_currentStatus == 'rescheduled' && _scheduledTime != null) ...[
            const SizedBox(height: AbashyakaSpacing.sm),
            _receiptField(
              'Proposed Appointment',
              DateFormat('EEE, MMM d, yyyy · h:mm a').format(_scheduledTime!),
            ),
          ],
          const SizedBox(height: AbashyakaSpacing.xs),
          Text(
            'Booking ID $_bookingId',
            style: const TextStyle(
              fontSize: 12,
              color: AbashyakaColors.graphiteCharcoal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(
    ({String title, String description, IconData icon, Color color}) status,
  ) {
    final closed =
        _currentStatus == 'cancelled' || _currentStatus == 'declined';
    final submitted = widget.request?.createdAt;
    final steps = [
      for (final stage in _stages)
        if ((!closed || stage.$1 == 'requested') &&
            (stage.$1 != 'en_route' || _currentStatus == 'en_route')) ...[
          stage,
          if (stage.$1 == 'accepted' && _currentStatus == 'rescheduled')
            ('rescheduled', status.title),
        ],
      if (closed) (_currentStatus, status.title),
    ];

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            closed || _currentStatus == 'completed'
                ? 'Request Timeline'
                : 'Live Progress Timeline',
          ),
          const SizedBox(height: AbashyakaSpacing.sm),
          for (final (index, step) in steps.indexed)
            _timelineRow(
              title: step.$2,
              current: step.$1 == _currentStatus,
              color: status.color,
              first: index == 0,
              last: index == steps.length - 1,
              detail: step.$1 == 'requested' && submitted != null
                  ? DateFormat('MMM d, h:mm a').format(submitted.toLocal())
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _timelineRow({
    required String title,
    required bool current,
    required Color color,
    required bool first,
    required bool last,
    String? detail,
  }) {
    return Stack(
      children: [
        PositionedDirectional(
          start: 11,
          top: first ? 20 : 0,
          bottom: last ? null : 0,
          height: last ? 20 : null,
          child: const ColoredBox(
            color: AbashyakaColors.silverGlass,
            child: SizedBox(width: 2),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AbashyakaSpacing.xs),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: current ? color : AbashyakaColors.pureWhite,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: current ? color : AbashyakaColors.silverGlass,
                    width: 2,
                  ),
                ),
                child: SizedBox.square(
                  dimension: 24,
                  child: current
                      ? const Icon(
                          Icons.circle,
                          size: 8,
                          color: AbashyakaColors.pureWhite,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: AbashyakaSpacing.sm),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: current ? AbashyakaColors.iceAquaWhite : null,
                  borderRadius: BorderRadius.circular(AbashyakaRadius.sm),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AbashyakaSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: current
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: AbashyakaColors.premiumObsidian,
                        ),
                      ),
                      if (current || detail != null)
                        Text(
                          [if (current) 'Current status', ?detail].join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AbashyakaColors.graphiteCharcoal,
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
    );
  }

  Widget _buildProfessionalCard() {
    final pro = widget.business;
    final rating = pro?.rating;
    final phone = pro?.phoneE164;
    final whatsapp = pro?.whatsappE164 ?? phone;

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading('Assigned Professional'),
          const SizedBox(height: AbashyakaSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconTile(
                Icons.person_outline_rounded,
                AbashyakaColors.signatureTeal,
              ),
              const SizedBox(width: AbashyakaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _providerName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AbashyakaColors.premiumObsidian,
                      ),
                    ),
                    if (pro?.isVerified ?? false)
                      const Text('Verified business'),
                    if (rating != null)
                      Text('Rating ${rating.toStringAsFixed(1)}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AbashyakaSpacing.sm),
          Wrap(
            spacing: AbashyakaSpacing.xs,
            runSpacing: AbashyakaSpacing.xxs,
            children: [
              OutlinedButton.icon(
                style: _outlineStyle(),
                onPressed: phone == null ? null : () => _makePhoneCall(phone),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Call Pro'),
              ),
              OutlinedButton.icon(
                style: _outlineStyle(),
                onPressed: whatsapp == null
                    ? null
                    : () => _openWhatsApp(whatsapp),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('WhatsApp'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceipt() {
    final appointment = _scheduledTime;
    final instructions = widget.request?.description;

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading('Job & Receipt Summary'),
          const SizedBox(height: AbashyakaSpacing.sm),
          _receiptField('Service Requested', _serviceTitle),
          _receiptField(
            _currentStatus == 'rescheduled'
                ? 'Proposed Appointment'
                : 'Appointment Slot',
            appointment == null
                ? 'Time not specified'
                : DateFormat('EEE, MMM d, yyyy · h:mm a').format(appointment),
          ),
          _receiptField('Indicative Estimate', 'Not provided'),
          if (instructions != null &&
              instructions.isNotEmpty &&
              instructions != _serviceTitle)
            _receiptField('Customer Instructions', instructions),
        ],
      ),
    );
  }

  Widget _receiptField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AbashyakaSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AbashyakaColors.graphiteCharcoal,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AbashyakaColors.premiumObsidian,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context, double scale) {
    final rescheduled = _currentStatus == 'rescheduled';
    final actions = [
      if (rescheduled)
        MetallicButton(
          buttonKey: const Key('customer_confirm_reschedule'),
          text: 'Confirm new time',
          height: scale + 36,
          isLoading: _isConfirmingReschedule,
          onPressed: _confirmProposedTime,
        ),
      if (_currentStatus != 'completed' && _currentStatus != 'cancelled')
        OutlinedButton(
          style: _outlineStyle(foreground: AbashyakaColors.error),
          onPressed: _showCancelConfirmationModal,
          child: const Text('Cancel'),
        ),
      OutlinedButton.icon(
        style: _outlineStyle(),
        onPressed: () =>
            Navigator.of(context).popUntil((route) => route.isFirst),
        icon: const Icon(Icons.home_outlined),
        label: Text(
          _currentStatus == 'completed' ? 'Back to Home' : 'Back to Explore',
        ),
      ),
    ];
    final stacked = rescheduled || scale > 24;

    return ColoredBox(
      color: AbashyakaColors.pureWhite,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AbashyakaSpacing.md,
            vertical: AbashyakaSpacing.xs,
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: AbashyakaSpacing.xxs,
                  children: actions,
                )
              : Row(
                  spacing: AbashyakaSpacing.xs,
                  children: [
                    for (final action in actions) Expanded(child: action),
                  ],
                ),
        ),
      ),
    );
  }

  ButtonStyle _outlineStyle({
    Color foreground = AbashyakaColors.signatureTeal,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: foreground,
      padding: const EdgeInsets.symmetric(
        horizontal: AbashyakaSpacing.sm,
        vertical: AbashyakaSpacing.xs,
      ),
      minimumSize: const Size(0, AbashyakaSpacing.touchTargetMin),
      side: const BorderSide(color: AbashyakaColors.silverGlass),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AbashyakaRadius.button),
      ),
    );
  }

  Widget _heading(String text) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AbashyakaColors.premiumObsidian,
        ),
      ),
    );
  }

  Widget _iconTile(IconData icon, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AbashyakaRadius.sm),
      ),
      child: SizedBox.square(
        dimension: 48,
        child: Icon(icon, size: 24, color: color),
      ),
    );
  }
}
