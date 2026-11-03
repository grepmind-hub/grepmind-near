import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../network/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_card.dart';

/// Merchant-managed date exceptions and appointment slot inventory.
class MerchantAvailabilityScreen extends StatefulWidget {
  const MerchantAvailabilityScreen({super.key});

  @override
  State<MerchantAvailabilityScreen> createState() =>
      _MerchantAvailabilityScreenState();
}

class _MerchantAvailabilityScreenState
    extends State<MerchantAvailabilityScreen> {
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  String? _businessId;
  String _timeZone = 'Asia/Kolkata';
  List<Map<String, dynamic>> _slots = [];
  List<Map<String, dynamic>> _exceptions = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profileResponse = await apiClient.get('/merchant/profile');
      final profile =
          (profileResponse.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final businessId = profile['id'] as String?;
      if (businessId == null || businessId.isEmpty) {
        throw StateError('Merchant business could not be identified.');
      }
      final response = await apiClient.get(
        '/merchant/businesses/$businessId/availability',
        queryParameters: {'from': _dateKey, 'to': _dateKey},
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _businessId = businessId;
        _timeZone = data['time_zone'] as String? ?? 'Asia/Kolkata';
        _slots = ((data['slots'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();
        _exceptions = ((data['exceptions'] as List<dynamic>?) ?? [])
            .cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load appointment availability. Please retry.';
        _loading = false;
      });
    }
  }

  Future<bool> _mutate(Future<void> Function(String businessId) action) async {
    final businessId = _businessId;
    if (businessId == null) return false;
    setState(() => _saving = true);
    try {
      await action(businessId);
      if (!mounted) return false;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Availability saved')));
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      final response = error is DioException ? error.response : null;
      var message =
          'Could not save availability. Check the date and try again.';
      if (response?.data is Map<String, dynamic>) {
        final body = response!.data as Map<String, dynamic>;
        final apiError = body['error'] as Map<String, dynamic>?;
        message =
            apiError?['message'] as String? ?? 'Could not save availability.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.error),
      );
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSlotEditor({Map<String, dynamic>? slot}) async {
    final dateController = TextEditingController(
      text: slot?['local_date'] as String? ?? _dateKey,
    );
    final capacityController = TextEditingController(
      text: '${slot?['capacity'] ?? 1}',
    );
    var start =
        _parseClock(slot?['local_starts_at'] as String?) ??
        const TimeOfDay(hour: 9, minute: 0);
    var end =
        _parseClock(slot?['local_ends_at'] as String?) ??
        const TimeOfDay(hour: 10, minute: 0);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7DEEA),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  slot == null
                      ? 'Add appointment slot'
                      : 'Edit appointment slot',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Local time • $_timeZone',
                  style: const TextStyle(color: AppTheme.secondaryText),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          DateTime.tryParse(dateController.text) ??
                          _selectedDate,
                      firstDate: DateUtils.dateOnly(DateTime.now()),
                      lastDate: DateUtils.dateOnly(
                        DateTime.now().add(const Duration(days: 180)),
                      ),
                    );
                    if (picked != null) {
                      dateController.text = DateFormat('yyyy-MM-dd')
                          .format(picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: start,
                          );
                          if (picked != null)
                            setSheetState(() => start = picked);
                        },
                        icon: const Icon(Icons.login_outlined),
                        label: Text('Start  ${start.format(context)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: end,
                          );
                          if (picked != null) setSheetState(() => end = picked);
                        },
                        icon: const Icon(Icons.logout_outlined),
                        label: Text('End  ${end.format(context)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: capacityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Concurrent bookings',
                    helperText: 'Choose 1–20 appointments for this time',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            final date = dateController.text;
                            final capacity = int.tryParse(
                              capacityController.text,
                            );
                            if (capacity == null ||
                                capacity < 1 ||
                                capacity > 20) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Capacity must be between 1 and 20.',
                                  ),
                                ),
                              );
                              return;
                            }
                            final succeeded = await _mutate((businessId) async {
                              final payload = {
                                'date': date,
                                'starts_at': _clock(start),
                                'ends_at': _clock(end),
                                'capacity': capacity,
                              };
                              if (slot == null) {
                                await apiClient.post(
                                  '/merchant/businesses/$businessId/availability-slots',
                                  data: payload,
                                );
                              } else {
                                await apiClient.patch(
                                  '/merchant/businesses/$businessId/availability-slots/${slot['id']}',
                                  data: payload,
                                );
                              }
                            });
                            if (succeeded && mounted) {
                              Navigator.of(sheetContext).pop(true);
                            }
                          },
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save slot'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    dateController.dispose();
    capacityController.dispose();
    if (saved == true) await _load();
  }

  Future<void> _manageDateException() async {
    final current = _exceptionForSelectedDate;
    var isClosed = current?['is_closed'] as bool? ?? false;
    var customHours = current?['opens_at'] != null;
    var start =
        _parseClock(current?['opens_at'] as String?) ??
        const TimeOfDay(hour: 9, minute: 0);
    var end =
        _parseClock(current?['closes_at'] as String?) ??
        const TimeOfDay(hour: 17, minute: 0);
    final noteController = TextEditingController(
      text: current?['note'] as String? ?? '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text(
                  'Date-specific hours',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEEE, d MMMM yyyy').format(_selectedDate),
                  style: const TextStyle(color: AppTheme.secondaryText),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Close this date'),
                  subtitle: const Text(
                    'Existing unbooked slots will be closed.',
                  ),
                  value: isClosed,
                  onChanged: (value) => setSheetState(() => isClosed = value),
                ),
                if (!isClosed) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Override weekly hours'),
                    value: customHours,
                    onChanged: (value) =>
                        setSheetState(() => customHours = value),
                  ),
                  if (customHours)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: start,
                              );
                              if (picked != null)
                                setSheetState(() => start = picked);
                            },
                            child: Text('Open  ${start.format(context)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: end,
                              );
                              if (picked != null)
                                setSheetState(() => end = picked);
                            },
                            child: Text('Close  ${end.format(context)}'),
                          ),
                        ),
                      ],
                    ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            final succeeded = await _mutate((businessId) async {
                              await apiClient.put(
                                '/merchant/businesses/$businessId/availability-exceptions',
                                data: {
                                  'date': _dateKey,
                                  'is_closed': isClosed,
                                  'opens_at': !isClosed && customHours
                                      ? _clock(start)
                                      : null,
                                  'closes_at': !isClosed && customHours
                                      ? _clock(end)
                                      : null,
                                  'note': noteController.text.trim(),
                                },
                              );
                            });
                            if (succeeded && mounted)
                              Navigator.of(sheetContext).pop();
                          },
                    child: const Text('Save date settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    noteController.dispose();
  }

  Map<String, dynamic>? get _exceptionForSelectedDate {
    for (final exception in _exceptions) {
      if (exception['date'] == _dateKey) return exception;
    }
    return null;
  }

  TimeOfDay? _parseClock(String? value) {
    if (value == null || value.length < 5) return null;
    final parts = value.substring(0, 5).split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _clock(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final exception = _exceptionForSelectedDate;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.event_busy,
                    size: 40,
                    color: AppTheme.secondaryText,
                  ),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  PremiumCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.public, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Business time zone',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            Text(
                              _timeZone,
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Appointment times are shown in your local business time and stored safely as UTC.',
                          style: TextStyle(
                            color: AppTheme.secondaryText,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 31,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final date = DateUtils.dateOnly(DateTime.now())
                            .add(Duration(days: index));
                        final selected = DateUtils.isSameDay(
                          date,
                          _selectedDate,
                        );
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() {
                            _selectedDate = date;
                            _load();
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 56,
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.primary : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primary
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat('E').format(date).substring(0, 2),
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white70
                                        : AppTheme.secondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : AppTheme.mainText,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('EEEE, d MMMM').format(_selectedDate),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _manageDateException,
                        icon: const Icon(Icons.event_busy_outlined, size: 18),
                        label: Text(
                          exception == null ? 'Date settings' : 'Edit date',
                        ),
                      ),
                    ],
                  ),
                  if (exception?['is_closed'] == true)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFFC2410C)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Closed for appointments on this date.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_slots.isEmpty)
                    PremiumCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.event_available_outlined,
                            size: 34,
                            color: AppTheme.secondaryText,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No appointment slots for this date',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Create real bookable times for customers.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.secondaryText),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: exception?['is_closed'] == true
                                ? null
                                : () => _openSlotEditor(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add appointment slot'),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._slots.map(_buildSlotCard),
                  if (_slots.isNotEmpty && exception?['is_closed'] != true)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: () => _openSlotEditor(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add another slot'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSlotCard(Map<String, dynamic> slot) {
    final status = slot['status'] as String? ?? 'closed';
    final booked = (slot['booked_count'] as num?)?.toInt() ?? 0;
    final capacity = (slot['capacity'] as num?)?.toInt() ?? 0;
    final canEdit = booked == 0 && status != 'closed';
    final start =
        _parseClock(slot['local_starts_at'] as String?) ??
        const TimeOfDay(hour: 0, minute: 0);
    final end =
        _parseClock(slot['local_ends_at'] as String?) ??
        const TimeOfDay(hour: 0, minute: 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PremiumCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: status == 'open'
                    ? const Color(0xFFE8F5F1)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                status == 'open' ? Icons.event_available : Icons.event_busy,
                color: status == 'open'
                    ? const Color(0xFF0F766E)
                    : AppTheme.secondaryText,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${start.format(context)} – ${end.format(context)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$booked of $capacity booked • ${status == 'open' ? 'Open' : 'Closed'}',
                    style: const TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (canEdit)
              PopupMenuButton<String>(
                tooltip: 'Slot actions',
                onSelected: (action) {
                  if (action == 'edit') {
                    _openSlotEditor(slot: slot);
                  } else {
                    _mutate((businessId) async {
                      await apiClient.patch(
                        '/merchant/businesses/$businessId/availability-slots/${slot['id']}',
                        data: {'status': 'closed'},
                      );
                    });
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit slot')),
                  PopupMenuItem(value: 'close', child: Text('Close slot')),
                ],
              )
            else
              const Tooltip(
                message: 'Booked or closed slots cannot be edited',
                child: Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: AppTheme.secondaryText,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
