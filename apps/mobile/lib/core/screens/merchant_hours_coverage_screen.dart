import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/business.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_card.dart';

class MerchantHoursCoverageScreen extends ConsumerStatefulWidget {
  const MerchantHoursCoverageScreen({super.key});

  @override
  ConsumerState<MerchantHoursCoverageScreen> createState() =>
      _MerchantHoursCoverageScreenState();
}

class _MerchantHoursCoverageScreenState
    extends ConsumerState<MerchantHoursCoverageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<String> _localities = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(merchantHoursCoverageProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatTimeDisplay(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '09:00 AM';
    final parts = timeStr.split(':');
    if (parts.length < 2) return timeStr;
    final hour = int.tryParse(parts[0]) ?? 9;
    final minute = int.tryParse(parts[1]) ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMinute $period';
  }

  String _timeOfDayToTimeString(TimeOfDay tod) {
    final h = tod.hour.toString().padLeft(2, '0');
    final m = tod.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  TimeOfDay _stringToTimeOfDay(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
    final parts = timeStr.split(':');
    if (parts.length < 2) return const TimeOfDay(hour: 9, minute: 0);
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  Future<void> _pickTime({
    required BuildContext context,
    required String? currentTime,
    required ValueChanged<String> onSelected,
  }) async {
    final initial = _stringToTimeOfDay(currentTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              onSurface: AppTheme.mainText,
            ),
          ),
          child: child ?? const SizedBox(),
        );
      },
    );
    if (picked != null) {
      onSelected(_timeOfDayToTimeString(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(merchantHoursCoverageProvider);
    final notifier = ref.read(merchantHoursCoverageProvider.notifier);

    // Show snackbar on success/error messages
    ref.listen<MerchantHoursCoverageState>(merchantHoursCoverageProvider, (
      prev,
      next,
    ) {
      if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(next.successMessage!)),
              ],
            ),
            backgroundColor: const Color(0xFF0F766E),
            behavior: SnackBarBehavior.floating,
          ),
        );
        notifier.clearMessages();
      }
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(next.error!)),
              ],
            ),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        notifier.clearMessages();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hours & Coverage',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            Text(
              state.businessName.isNotEmpty
                  ? state.businessName
                  : 'Merchant Setup',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.secondaryText,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.schedule), text: 'Operating Hours'),
            Tab(icon: Icon(Icons.radar), text: 'Service Coverage'),
          ],
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _tabController.index,
              children: [
                _buildOperatingHoursTab(state, notifier),
                _buildServiceCoverageTab(state, notifier),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(
        label: _tabController.index == 0
            ? 'Save Operating Hours'
            : 'Save Coverage Settings',
        isSaving: state.isSaving,
        onPressed: _tabController.index == 0
            ? () => notifier.saveOperatingHours()
            : () => notifier.saveCoverage(),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: OPERATING HOURS
  // -------------------------------------------------------------
  Widget _buildOperatingHoursTab(
    MerchantHoursCoverageState state,
    MerchantHoursCoverageNotifier notifier,
  ) {
    final displayHours = state.hours;
    return SingleChildScrollView(
      key: const PageStorageKey('scroll_operating_hours'),
      padding: const EdgeInsets.all(kScreenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppTheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Set weekly store & booking hours. Customers see real-time "Open Now" or "Closed" statuses.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.mainText,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick Actions Toolbar
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_all, size: 16),
                label: const Text(
                  'Mon \u2192 Mon-Fri',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => notifier.copyDayToWeekdays(1),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 14,
                  ),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => notifier.setAllDaysOpen(true),
                child: const Text('All Open', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 14,
                  ),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => notifier.setAllDaysOpen(false),
                child: const Text('All Closed', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (displayHours.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: 32,
                    color: AppTheme.secondaryText,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No operating hours published',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Create a draft schedule, review it, then save it for customers.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: notifier.initializeHoursDraft,
                    child: const Text('Create schedule draft'),
                  ),
                ],
              ),
            )
          else
            ...displayHours.map((hour) => _buildDayRow(hour, notifier)),

          const SizedBox(height: 16),

          // Holiday / Exceptions Note
          PremiumCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.event_busy,
                      color: Color(0xFF0F766E),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Special Holiday Hours',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mainText,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Special holiday exception modal ready.',
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        '+ Add Exception',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Override your standard weekly hours for festivals, national holidays, or planned shop maintenance.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.secondaryText,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDayRow(
    BusinessHour hour,
    MerchantHoursCoverageNotifier notifier,
  ) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const fullDays = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final dayLabel = fullDays[hour.weekday.clamp(0, 6)];
    final shortLabel = days[hour.weekday.clamp(0, 6)];
    final isWeekend = hour.weekday == 0 || hour.weekday == 6;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hour.isClosed
                ? const Color(0xFFE2E8F0)
                : AppTheme.primary.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                // Day Pill
                Container(
                  width: 44,
                  height: 34,
                  decoration: BoxDecoration(
                    color: hour.isClosed
                        ? const Color(0xFFF1F5F9)
                        : (isWeekend
                              ? const Color(0xFF0F766E).withOpacity(0.12)
                              : AppTheme.primary.withOpacity(0.1)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    shortLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: hour.isClosed
                          ? AppTheme.secondaryText
                          : (isWeekend
                                ? const Color(0xFF0F766E)
                                : AppTheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: hour.isClosed
                              ? AppTheme.secondaryText
                              : AppTheme.mainText,
                        ),
                      ),
                      Text(
                        hour.isClosed ? 'Closed all day' : 'Open for business',
                        style: TextStyle(
                          fontSize: 12,
                          color: hour.isClosed
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: !hour.isClosed,
                  activeColor: AppTheme.primary,
                  onChanged: (open) {
                    notifier.updateDayHour(hour.weekday, isClosed: !open);
                  },
                ),
              ],
            ),

            // Time range row if open
            if (!hour.isClosed) ...[
              const Divider(height: 18),
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 16,
                    color: AppTheme.secondaryText,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Hours:',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                  const Spacer(),
                  // Open Time Button
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      _pickTime(
                        context: context,
                        currentTime: hour.opensAt,
                        onSelected: (time) {
                          notifier.updateDayHour(hour.weekday, opensAt: time);
                        },
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        _formatTimeDisplay(hour.opensAt),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.mainText,
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'to',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ),
                  // Close Time Button
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      _pickTime(
                        context: context,
                        currentTime: hour.closesAt,
                        onSelected: (time) {
                          notifier.updateDayHour(hour.weekday, closesAt: time);
                        },
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        _formatTimeDisplay(hour.closesAt),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.mainText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: SERVICE COVERAGE
  // -------------------------------------------------------------
  Widget _buildServiceCoverageTab(
    MerchantHoursCoverageState state,
    MerchantHoursCoverageNotifier notifier,
  ) {
    final radiusKm = (state.serviceRadiusM / 1000).toStringAsFixed(1);
    final approxArea =
        (3.14159 *
                (state.serviceRadiusM / 1000) *
                (state.serviceRadiusM / 1000))
            .toStringAsFixed(0);

    return SingleChildScrollView(
      key: const PageStorageKey('scroll_service_coverage'),
      padding: const EdgeInsets.all(kScreenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Store Location Summary
          PremiumCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Color(0xFF0F766E),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Base Service Hub',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${state.locality}, ${state.city}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.mainText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lat: ${state.latitude.toStringAsFixed(4)}, Lon: ${state.longitude.toStringAsFixed(4)}',
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
          const SizedBox(height: 18),

          // Radius Setup Card
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Service Radius',
                      style: TextStyle(
                        fontSize: 16,
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
                        color: AppTheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$radiusKm km radius',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'You will receive requests and appear to customers within ~$approxArea sq km.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.secondaryText,
                  ),
                ),
                const SizedBox(height: 20),

                // Slider
                Slider(
                  value: state.serviceRadiusM.toDouble().clamp(1000.0, 50000.0),
                  min: 1000.0,
                  max: 50000.0,
                  divisions: 49,
                  activeColor: AppTheme.primary,
                  inactiveColor: const Color(0xFFE2E8F0),
                  onChanged: (val) {
                    notifier.setServiceRadius(val.toInt());
                  },
                ),

                // Preset Radius Chips
                Wrap(
                  spacing: 8,
                  children: [2000, 5000, 10000, 15000, 25000].map((meters) {
                    final isSelected = state.serviceRadiusM == meters;
                    final km = meters ~/ 1000;
                    return ChoiceChip(
                      label: Text('$km km'),
                      selected: isSelected,
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.mainText,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      onSelected: (_) => notifier.setServiceRadius(meters),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Localities Served
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Coverage Localities',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mainText,
                      ),
                    ),
                    Text(
                      '${_localities.length} Areas',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Primary localities within your configured delivery and service zone.',
                  style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._localities.map(
                      (loc) => Chip(
                        backgroundColor: const Color(0xFFF1F5F9),
                        avatar: const Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Color(0xFF0F766E),
                        ),
                        label: Text(
                          loc,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () {
                          setState(() {
                            _localities.remove(loc);
                          });
                        },
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.add,
                        size: 16,
                        color: AppTheme.primary,
                      ),
                      label: const Text(
                        'Add Area',
                        style: TextStyle(color: AppTheme.primary, fontSize: 12),
                      ),
                      onPressed: () => _showAddLocalityDialog(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // On-Demand / Urgent Requests Toggle
          PremiumCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: state.acceptsRequests
                        ? const Color(0xFF16A34A).withOpacity(0.1)
                        : const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    state.acceptsRequests ? Icons.flash_on : Icons.flash_off,
                    color: state.acceptsRequests
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFEF4444),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Accept Immediate Bookings',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.mainText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.acceptsRequests
                            ? 'Your profile is live for customer direct inquiries'
                            : 'Currently paused for new service requests',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: state.acceptsRequests,
                  activeColor: const Color(0xFF16A34A),
                  onChanged: (val) {
                    notifier.toggleAcceptsRequests(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBottomBar({
    required String label,
    required bool isSaving,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isSaving ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _showAddLocalityDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Add Service Locality',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Whitefield, Bellandur',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final txt = textController.text.trim();
                if (txt.isNotEmpty) {
                  setState(() {
                    if (!_localities.contains(txt)) {
                      _localities.add(txt);
                    }
                  });
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}
