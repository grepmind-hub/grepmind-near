import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/service_request_status_screen.dart';

/// Screen 15: Appointment Slot Scheduler.
///
/// Features:
/// - Provider mini header with ratings and hourly rates
/// - Service & scope selection
/// - Interactive horizontal calendar day strip
/// - Categorized time slots (Morning, Afternoon, Evening)
/// - Job instructions / notes
/// - Sticky bottom bar with pricing & "Confirm Booking" CTA
/// - Animated confirmation sheet with booking reference ID
class BookingSchedulerScreen extends ConsumerStatefulWidget {
  final Business? business;
  final String? businessId;
  final String? businessName;
  final Service? selectedService;

  const BookingSchedulerScreen({
    super.key,
    this.business,
    this.businessId,
    this.businessName,
    this.selectedService,
  });

  @override
  ConsumerState<BookingSchedulerScreen> createState() => _BookingSchedulerScreenState();
}

class _BookingSchedulerScreenState extends ConsumerState<BookingSchedulerScreen> {
  late DateTime _selectedDate;
  String? _selectedSlotTime;
  Service? _currentService;
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  // Selected scope (when no specific service chosen)
  int _selectedScopeIndex = 0;
  final List<Map<String, dynamic>> _scopeOptions = [
    {'title': 'Standard Visit', 'duration': '45-60 mins', 'price': 299},
    {'title': 'Full Inspection', 'duration': '60-90 mins', 'price': 499},
    {'title': 'Major Repair', 'duration': '2-3 hours', 'price': 899},
    {'title': 'Emergency Visit', 'duration': 'Immediate', 'price': 699},
  ];

  late final List<DateTime> _calendarDays;

  @override
  void initState() {
    super.initState();
    _currentService = widget.selectedService;
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);

    // Generate 14 days starting from today
    _calendarDays = List.generate(
      14,
      (index) => DateTime(now.year, now.month, now.day).add(Duration(days: index)),
    );

    // Default slot for today
    _selectedSlotTime = '10:00 AM';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String get _providerName {
    if (widget.business?.name != null && widget.business!.name.isNotEmpty) {
      return widget.business!.name;
    }
    if (widget.businessName != null && widget.businessName!.isNotEmpty) {
      return widget.businessName!;
    }
    return 'Service Professional';
  }

  String get _providerShortName {
    final parts = _providerName.split(' ');
    if (parts.isNotEmpty) return parts.first;
    return 'Pro';
  }

  int get _calculatedPrice {
    if (_currentService != null) {
      if (_currentService!.indicativePriceMin != null) {
        return _currentService!.indicativePriceMin!.round();
      }
    }
    return _scopeOptions[_selectedScopeIndex]['price'] as int;
  }

  List<String> _getMorningSlots() => ['08:30 AM', '10:00 AM', '11:30 AM'];
  List<String> _getAfternoonSlots() => ['01:00 PM', '02:30 PM', '03:30 PM'];
  List<String> _getEveningSlots() => ['05:00 PM', '06:30 PM', '07:30 PM'];

  bool _isSlotBooked(String slotTime) {
    // Demo realistic scenario: tomorrow 11:30 AM is booked
    final isTomorrow = _selectedDate.day == (DateTime.now().day + 1);
    if (isTomorrow && slotTime == '11:30 AM') return true;
    return false;
  }

  Future<void> _confirmBooking() async {
    if (_selectedSlotTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an appointment time slot'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final bizId = widget.business?.id ?? widget.businessId;
      if (bizId == null || bizId.isEmpty) throw StateError('Business required');
      final description = _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : (_currentService != null
              ? 'Appointment booking for ${_currentService!.name}'
              : 'Service appointment for ${_scopeOptions[_selectedScopeIndex]['title']}');

      String? createdId;
      // Live API booking call to Grepmind Near backend
      try {
        final res = await apiClient.post(
          '/businesses/$bizId/requests',
          data: {
            'service_id': _currentService?.id,
            'description': '$description [Slot: $_selectedSlotTime]',
            'requested_for': _selectedDate.toIso8601String(),
          },
        );
        final data = res.data as Map<String, dynamic>;
        createdId = (data['data'] as Map<String, dynamic>?)?['id'] as String?;
      } catch (_) { rethrow; }
      if (createdId == null || createdId.isEmpty) throw StateError('Booking was not persisted');

      await Future.delayed(const Duration(milliseconds: 400));

      if (mounted) {
        _showSuccessConfirmationSheet(createdId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to book. Check your connection and sign in, then try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessConfirmationSheet([String? realReqId]) {
    final dateFormat = DateFormat('EEE, MMM d, yyyy');
    final formattedDate = dateFormat.format(_selectedDate);
    final bookingId = realReqId != null
        ? '#GN-${realReqId.substring(0, 6).toUpperCase()}'
        : 'GN-${(1000 + DateTime.now().millisecond * 7).toString().padLeft(4, '0')}';

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
          children: [
            // Handle bar
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),

            // Animated Success Circle Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFA7F3D0), width: 2),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF059669),
                size: 46,
              ),
            ),
            const SizedBox(height: 18),

            const Text(
              'Booking Requested!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.mainText,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$_providerShortName will confirm within 15 minutes.\nYou can track the live status anytime.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.secondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Booking Details Receipt Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildReceiptRow('Booking ID', '#$bookingId', isBold: true),
                  const Divider(height: 20, color: Color(0xFFE2E8F0)),
                  _buildReceiptRow('Professional', _providerName),
                  const SizedBox(height: 8),
                  _buildReceiptRow(
                    'Service',
                    _currentService?.name ?? _scopeOptions[_selectedScopeIndex]['title'] as String,
                  ),
                  const SizedBox(height: 8),
                  _buildReceiptRow('Date & Time', '$formattedDate • $_selectedSlotTime'),
                  const SizedBox(height: 8),
                  _buildReceiptRow('Location', 'Saheed Nagar, Plot 42'),
                  const Divider(height: 20, color: Color(0xFFE2E8F0)),
                  _buildReceiptRow('Estimated Amount', '₹$_calculatedPrice', isBold: true, isHighlight: true),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.primary, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceRequestStatusScreen(
                            requestId: realReqId,
                            business: widget.business,
                            businessName: widget.businessName,
                            serviceName: _currentService?.name ?? _scopeOptions[_selectedScopeIndex]['title'] as String,
                            appointmentTime: _selectedDate,
                            initialStatus: 'requested',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Track Live Status',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppTheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'Done',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isBold = false, bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: isHighlight ? AppTheme.primary : AppTheme.mainText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthFormat = DateFormat('MMMM yyyy');
    final formattedMonth = monthFormat.format(_selectedDate);

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
        title: Text(
          'Schedule $_providerShortName',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.mainText,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_border_rounded, color: AppTheme.mainText),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Saved $_providerShortName for later')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppTheme.mainText),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _buildProProfileHeader(),
          const SizedBox(height: 16),
          _buildServiceScopeSection(),
          const SizedBox(height: 18),
          _buildDateSelectionStrip(formattedMonth),
          const SizedBox(height: 20),
          _buildTimeSlotsSection(),
          const SizedBox(height: 20),
          _buildNotesAndLocationCard(),
        ],
      ),
      bottomNavigationBar: _buildStickyBottomBar(),
    );
  }

  Widget _buildProProfileHeader() {
    final pro = widget.business;
    final rating = pro?.rating ?? 4.9;
    final locality = pro?.locality ?? 'Saheed Nagar';
    final city = pro?.city ?? 'Bhubaneswar';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pro Avatar with Badge
          Stack(
            children: [
              Container(
                width: 54,
                height: 54,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2457D6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 10, color: Colors.white),
                ),
              ),
            ],
          ),

          const SizedBox(width: 14),

          // Pro Details
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _providerName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.mainText,
                        ),
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
                    Flexible(
                      child: Text(
                        '$rating (124+ completed)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mainText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$locality, $city • 1.8 km',
                  style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                ),
              ],
            ),
          ),

          // Hourly / Base Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: const Text(
              '₹299/hr',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceScopeSection() {
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
              const Text(
                'Job Scope & Duration',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                ),
              ),
              if (_currentService != null)
                GestureDetector(
                  onTap: () {
                    setState(() => _currentService = null);
                  },
                  child: const Text(
                    'Change Scope',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_currentService != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.build_circle_outlined, color: AppTheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentService!.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.mainText),
                        ),
                        const SizedBox(height: 2),
                        const Text('Est. duration: 45 - 60 mins', style: TextStyle(fontSize: 11, color: AppTheme.secondaryText)),
                      ],
                    ),
                  ),
                  Text(
                    _currentService!.priceText,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.primary),
                  ),
                ],
              ),
            )
          else
            // Scope Chips Carousel
            SizedBox(
              height: 68,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                children: List.generate(_scopeOptions.length, (index) {
                  final scope = _scopeOptions[index];
                  final isSelected = _selectedScopeIndex == index;
                  return Padding(
                    padding: EdgeInsets.only(right: index == _scopeOptions.length - 1 ? 0 : 10),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedScopeIndex = index),
                      child: Container(
                        width: 144,
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              scope['title'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? AppTheme.primary : AppTheme.mainText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    scope['duration'] as String,
                                    style: const TextStyle(fontSize: 10, color: AppTheme.secondaryText),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '₹${scope['price']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected ? AppTheme.primary : AppTheme.mainText,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelectionStrip(String formattedMonth) {
    final dayNameFormat = DateFormat('EEE'); // e.g. SUN, MON

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
          // Month header with selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Select a Date',
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formattedMonth,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mainText,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppTheme.secondaryText),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Date horizontal carousel
          SizedBox(
            height: 76,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
              children: List.generate(_calendarDays.length, (index) {
                final date = _calendarDays[index];
                final isSelected = date.year == _selectedDate.year &&
                    date.month == _selectedDate.month &&
                    date.day == _selectedDate.day;
                final isToday = date.day == DateTime.now().day && date.month == DateTime.now().month;

                return Padding(
                  padding: EdgeInsets.only(right: index == _calendarDays.length - 1 ? 0 : 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedDate = date;
                        // reset selected slot when changing date if slot is not available
                        if (_isSlotBooked(_selectedSlotTime ?? '')) {
                          _selectedSlotTime = '10:00 AM';
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      height: 72,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dayNameFormat.format(date).toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white.withValues(alpha: 0.85) : AppTheme.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : AppTheme.mainText,
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(height: 2),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? Colors.white : AppTheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildTimeSlotsSection() {
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
                  'Available Time Slots',
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
                child: const Text(
                  '9 Slots Available',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Morning Slots
          _buildPeriodSlots(
            periodTitle: 'Morning',
            timeRange: '8:00 AM - 12:00 PM',
            icon: Icons.wb_sunny_outlined,
            iconColor: const Color(0xFFF59E0B),
            slots: _getMorningSlots(),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),

          // Afternoon Slots
          _buildPeriodSlots(
            periodTitle: 'Afternoon',
            timeRange: '12:00 PM - 04:00 PM',
            icon: Icons.wb_sunny_rounded,
            iconColor: const Color(0xFFEA580C),
            slots: _getAfternoonSlots(),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),

          // Evening Slots
          _buildPeriodSlots(
            periodTitle: 'Evening',
            timeRange: '04:00 PM - 08:00 PM',
            icon: Icons.nightlight_round,
            iconColor: const Color(0xFF4F46E5),
            slots: _getEveningSlots(),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSlots({
    required String periodTitle,
    required String timeRange,
    required IconData icon,
    required Color iconColor,
    required List<String> slots,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(
              periodTitle,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.mainText,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '($timeRange)',
                style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: slots.map((slot) {
            final isBooked = _isSlotBooked(slot);
            final isSelected = _selectedSlotTime == slot;

            return GestureDetector(
              onTap: isBooked
                  ? null
                  : () {
                      setState(() => _selectedSlotTime = slot);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isBooked
                      ? const Color(0xFFF1F5F9)
                      : isSelected
                          ? AppTheme.primary
                          : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBooked
                        ? const Color(0xFFE2E8F0)
                        : isSelected
                            ? AppTheme.primary
                            : const Color(0xFFCBD5E1),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isBooked
                          ? Icons.block_rounded
                          : isSelected
                              ? Icons.check_circle_rounded
                              : Icons.schedule_rounded,
                      size: 14,
                      color: isBooked
                          ? const Color(0xFF94A3B8)
                          : isSelected
                              ? Colors.white
                              : AppTheme.secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      slot,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isBooked
                            ? const Color(0xFF94A3B8)
                            : isSelected
                                ? Colors.white
                                : AppTheme.mainText,
                        decoration: isBooked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (isBooked) ...[
                      const SizedBox(width: 4),
                      const Text(
                        'Booked',
                        style: TextStyle(fontSize: 10, color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNotesAndLocationCard() {
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
            'Job Details & Address',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.mainText,
            ),
          ),
          const SizedBox(height: 12),

          // Address preview pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Service Address',
                        style: TextStyle(fontSize: 11, color: AppTheme.secondaryText, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Plot 42, Saheed Nagar, Bhubaneswar (Home)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Change',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Notes TextField
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add special instructions for $_providerShortName (e.g. bring 16A switch, ladder needed)...',
              hintStyle: const TextStyle(fontSize: 12, color: AppTheme.hintText),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar() {
    final dayFormat = DateFormat('EEE, MMM d');
    final formattedDay = dayFormat.format(_selectedDate);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE2E8F0)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
        children: [
          // Price & Slot Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₹$_calculatedPrice',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.mainText,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$formattedDay • ${_selectedSlotTime ?? 'Select slot'}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Confirm Booking CTA
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size(120, 48),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isSubmitting ? null : _confirmBooking,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Book $_providerShortName',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}
