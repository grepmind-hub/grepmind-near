import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class RiderDashboardScreen extends StatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  State<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends State<RiderDashboardScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _online = false;
  bool _busy = false;
  List<Map<String, dynamic>> _offers = [];
  Timer? _pollTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 25), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await apiClient.get('/rider/profile');
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      if (mounted) {
        setState(() => _profile = data);
      }
      final availability = await apiClient.get('/rider/availability');
      final availabilityData =
          (availability.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final offers = await apiClient.get('/rider/offers');
      final offerData =
          ((offers.data as Map<String, dynamic>)['data'] as List<dynamic>? ??
                  const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
      if (mounted) {
        setState(() {
          _online = availabilityData['online'] == true;
          _offers = offerData;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Rider access could not be refreshed. Contact support if your approval was changed.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _poll() async {
    if (!mounted) return;
    try {
      if (_online) await apiClient.post('/rider/availability/heartbeat');
      final response = await apiClient.get('/rider/offers');
      final data =
          ((response.data as Map<String, dynamic>)['data'] as List<dynamic>? ??
                  const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
      if (mounted) setState(() => _offers = data);
    } catch (_) {
      // The server lease expires safely if connectivity is lost.
    }
  }

  Future<void> _setOnline(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await apiClient.put(
        '/rider/availability',
        data: {'online': value},
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      if (mounted) setState(() => _online = data['online'] == true);
      await _poll();
    } on DioException catch (error) {
      if (mounted) {
        setState(() => _error = riderAvailabilityErrorMessage(error));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Availability could not be updated. Refresh status and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(String offerId, bool accept) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await apiClient.post(
        '/rider/offers/$offerId/${accept ? 'accept' : 'decline'}',
      );
      await _load();
    } on DioException catch (error) {
      if (mounted) {
        setState(() => _error = riderOfferErrorMessage(error));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The offer response could not be confirmed. Refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Rider dashboard'),
        backgroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD8E3F5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: AppTheme.primary,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _profile == null
                        ? 'Rider access status'
                        : 'Rider access approved',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Dispatch availability is controlled by approved service localities. No GPS is collected.',
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (_profile != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _profile!['display_name']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vehicle · ${(_profile!['vehicle_type']?.toString() ?? '').replaceAll('_', ' ')}',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Approved service localities',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final place
                        in (_profile!['approved_localities']
                                    as List<dynamic>? ??
                                [])
                            .whereType<Map<String, dynamic>>())
                      Text('• ${place['name']}, ${place['district']}'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD8E3F5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Delivery availability',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      if (_busy)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      Switch(
                        value: _online,
                        onChanged: _busy || _profile == null
                            ? null
                            : _setOnline,
                      ),
                    ],
                  ),
                  Text(
                    _online ? 'You are online for approved localities.' : 'You are offline and will not receive delivery offers.',
                    style: const TextStyle(color: AppTheme.secondaryText),
                  ),
                  if (_online)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Availability renews while this app is active. Go online again if it expires.',
                        style: TextStyle(
                          color: Colors.blueGrey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD8E3F5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Incoming offers',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const SizedBox(height: 10),
                  if (_offers.isEmpty)
                    Text(
                      _online ? 'No delivery offers right now.' : 'Go online to receive offers for your approved localities.',
                      style: const TextStyle(color: AppTheme.secondaryText),
                    ),
                  for (final item in _offers)
                    _OfferCard(
                      offer: item,
                      busy: _busy,
                      onAccept: () => _respond(item['id'].toString(), true),
                      onDecline: () => _respond(item['id'].toString(), false),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _PhaseNotice(
              title: 'Map & location',
              body: 'Live GPS tracking is not enabled. No location is collected in this phase.',
            ),
            const SizedBox(height: 12),
            const _PhaseNotice(
              title: 'Earnings',
              body: 'There are no delivery earnings or payouts to display yet.',
            ),
          ],
        ),
      ),
    );
  }
}

String riderOfferErrorMessage(DioException error) {
  final payload = error.response?.data;
  final detail = payload is Map ? payload['error'] : null;
  final code = detail is Map ? detail['code']?.toString() : null;
  switch (code) {
    case 'OFFER_EXPIRED':
    case 'OFFER_CLOSED':
      return 'This offer is no longer available. Refresh for current dispatch status.';
    case 'RIDER_UNAVAILABLE':
      return 'You cannot accept this offer while another delivery or rider offer is active.';
    case 'RIDER_NOT_APPROVED':
    case 'LOCALITY_NOT_APPROVED':
      return 'Your rider access or approved service locality changed. Contact operations.';
    case 'UNAUTHORIZED':
    case 'SESSION_REVOKED':
      return 'Your session needs to be renewed before accepting an offer.';
  }
  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout) {
    return 'Network interruption. Reconnect and refresh before accepting the offer.';
  }
  return 'The offer response was not accepted. Refresh to see current dispatch status.';
}

String riderAvailabilityErrorMessage(DioException error) {
  final payload = error.response?.data;
  final detail = payload is Map ? payload['error'] : null;
  final code = detail is Map ? detail['code']?.toString() : null;
  switch (code) {
    case 'RIDER_UNAVAILABLE':
      return 'Your active delivery or offer must be completed or resolved before going online for new offers.';
    case 'RIDER_NOT_APPROVED':
    case 'LOCALITY_NOT_APPROVED':
      return 'Your rider access or approved service locality changed. Contact operations.';
    case 'UNAUTHORIZED':
    case 'SESSION_REVOKED':
      return 'Your session needs to be renewed before changing availability.';
  }
  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout) {
    return 'Network interruption. Reconnect and try again.';
  }
  return 'Availability could not be updated. Refresh status and try again.';
}

class RiderDeliveriesScreen extends StatefulWidget {
  const RiderDeliveriesScreen({super.key});
  @override
  State<RiderDeliveriesScreen> createState() => _RiderDeliveriesScreenState();
}

class _RiderDeliveriesScreenState extends State<RiderDeliveriesScreen> {
  Map<String, dynamic>? _assignment;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _successMessage;
  Timer? _timer;
  String? _recoveryIdempotencyKey;
  String? _recoveryKeyReason;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final res = await apiClient.get('/rider/assignments/active');
      if (mounted) {
        setState(() {
          final assignment =
              (res.data as Map<String, dynamic>)['data']
                  as Map<String, dynamic>?;
          _assignment = assignment;
          final state = assignment?['execution_state']?.toString();
          if (_successMessage?.startsWith('Report received') == true &&
              (assignment == null ||
                  const {
                    'return_required',
                    'return_in_progress',
                    'returned',
                    'cancelled',
                    'delivered',
                  }.contains(state))) {
            // The recovery banner describes the state when the rider filed
            // the report. Once the server supplies the next operational state,
            // the assignment card itself becomes the authoritative instruction.
            _successMessage = null;
          }
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Active delivery could not be refreshed.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _transition(String state) async {
    final jobId = _assignment?['job_id']?.toString();
    if (jobId == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await apiClient.post(
        '/rider/delivery-jobs/$jobId/state',
        data: {'state': state},
      );
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'That delivery update was not accepted. Refresh and check the current state.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askCode(String title, String prompt) async {
    return showDialog<String>(
      context: context,
      builder: (_) =>
          _RiderTextEntryDialog(title: title, label: prompt, numeric: true),
    );
  }

  Future<void> _verifyPickup() async {
    final code = await _askCode('Verify pickup', '8-digit partner code');
    if (code == null || code.length != 8 || _busy) return;
    final jobId = _assignment?['job_id']?.toString();
    if (jobId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await apiClient.post(
        '/rider/delivery-jobs/$jobId/pickup/verify',
        data: {'code': code},
      );
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Pickup verification failed. Check the partner code and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelivery() async {
    final code = await _askCode(
      'Confirm customer handover',
      '8-digit customer code',
    );
    if (code == null || code.length != 8 || _busy) return;
    final jobId = _assignment?['job_id']?.toString();
    if (jobId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await apiClient.post(
        '/rider/delivery-jobs/$jobId/delivery/confirm',
        data: {'code': code},
      );
      if (mounted) {
        setState(
          () => _successMessage =
              'Delivery completed with customer verification.',
        );
      }
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Customer verification failed. The order was not marked delivered.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reportException() async {
    final jobId = _assignment?['job_id']?.toString();
    final state = _assignment?['execution_state']?.toString();
    if (jobId == null || _busy) return;
    final options = state == 'en_route'
        ? const {
            'customer_unreachable': 'Customer unreachable',
            'delivery_failed': 'Delivery failed',
          }
        : const {'pickup_failed': 'Pickup failed'};
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Report a delivery issue'),
        children: [
          for (final entry in options.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    );
    if (selected == null) return;
    if (!mounted) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RiderTextEntryDialog(
        title: 'Add details',
        label: 'Describe what happened (at least 10 characters).',
        maxLength: 470,
        multiline: true,
      ),
    );
    if (reason == null || reason.length < 10) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await apiClient.post(
        '/rider/delivery-jobs/$jobId/exceptions',
        data: {'type': selected, 'reason': reason},
      );
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The issue could not be recorded. Refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _newRecoveryKey() => List<int>.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  Future<void> _reportUnableToContinue() async {
    final jobId = _assignment?['job_id']?.toString();
    if (jobId == null || _busy) return;
    const choices = [
      'Vehicle issue',
      'Health or safety issue',
      'Road or access blocked',
      'Partner handover issue',
      'Other operational issue',
    ];
    final category = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Unable to continue?'),
        children: [
          for (final choice in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, choice),
              child: Text(choice),
            ),
        ],
      ),
    );
    if (category == null || !mounted) return;
    final details = await showDialog<String>(
      context: context,
      builder: (_) => const _RiderTextEntryDialog(
        title: 'Describe the issue',
        label: 'Give operations enough detail to help (10–500 characters).',
        maxLength: 500,
        multiline: true,
      ),
    );
    if (details == null || !mounted) return;
    final reason = '$category: ${details.trim()}';
    if (reason.length < 10 || reason.length > 500) {
      setState(
        () =>
            _error = 'Keep the incident details between 10 and 500 characters.',
      );
      return;
    }
    final requestFingerprint = '$jobId:$reason';
    if (_recoveryKeyReason != requestFingerprint) {
      _recoveryIdempotencyKey = _newRecoveryKey();
      _recoveryKeyReason = requestFingerprint;
    }
    setState(() {
      _busy = true;
      _error = null;
      _successMessage = null;
    });
    try {
      final response = await apiClient.post(
        '/rider/delivery-jobs/$jobId/unable-to-continue',
        data: {'reason': reason},
        options: Options(headers: {'Idempotency-Key': _recoveryIdempotencyKey}),
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>?;
      if (mounted) {
        setState(
          () => _successMessage =
              'Report received (${data?['state'] ?? 'open'}). You remain assigned until operations confirms a safe next step.',
        );
      }
      _recoveryIdempotencyKey = null;
      _recoveryKeyReason = null;
      await _load();
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) {
        _recoveryIdempotencyKey = null;
        _recoveryKeyReason = null;
      }
      if (mounted) {
        setState(
          () => _error = error.response?.statusCode == 409
              ? 'The assignment changed. Refresh to see the latest recovery status.'
              : 'The report was not confirmed. Retry safely; the same request key prevents duplicate records.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'The report could not be confirmed. Refresh and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text('Deliveries'),
      backgroundColor: Colors.white,
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_successMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F7EF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _successMessage!,
                style: const TextStyle(
                  color: Color(0xFF176B43),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (_assignment == null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.delivery_dining_outlined,
                    size: 42,
                    color: AppTheme.primary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No active delivery',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Accepted delivery assignments will appear here. Status updates require server confirmation.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          if (_assignment != null)
            _AssignmentCard(
              value: _assignment!,
              busy: _busy,
              onTransition: _transition,
              onVerifyPickup: _verifyPickup,
              onConfirmDelivery: _confirmDelivery,
              onException: _reportException,
              onUnableToContinue: _reportUnableToContinue,
            ),
        ],
      ),
    ),
  );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });
  final Map<String, dynamic> offer;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8FF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          offer['pickup_business']?.toString() ?? 'Partner pickup',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          '${offer['vertical'] ?? 'Order'} · ${offer['destination_locality'] ?? ''}, ${offer['destination_district'] ?? ''}',
        ),
        if (offer['pickup_address'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Pickup · ${offer['pickup_address']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: 10),
        for (final line
            in (offer['items'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>())
          Text(
            '${line['quantity']} × ${line['product_name']} ${line['variant_name'] ?? ''}',
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onDecline,
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : onAccept,
                child: const Text('Accept'),
              ),
            ),
          ],
        ),
        Text(
          'Offer expires ${offer['expires_at'] ?? ''}',
          style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
        ),
      ],
    ),
  );
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.value,
    required this.busy,
    required this.onTransition,
    required this.onVerifyPickup,
    required this.onConfirmDelivery,
    required this.onException,
    required this.onUnableToContinue,
  });
  final Map<String, dynamic> value;
  final bool busy;
  final ValueChanged<String> onTransition;
  final VoidCallback onVerifyPickup,
      onConfirmDelivery,
      onException,
      onUnableToContinue;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFD8E3F5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Assigned delivery',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          value['pickup_business']?.toString() ?? 'Partner',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if ((value['pickup_address']?.toString() ?? '').isNotEmpty)
          Text('Pickup · ${value['pickup_address']}'),
        const SizedBox(height: 8),
        Text(
          'Delivery · ${value['recipient_name'] ?? 'Customer'} · ${value['destination_address'] ?? '${value['destination_locality'] ?? ''}, ${value['destination_district'] ?? ''}'}',
        ),
        if ((value['contact_phone']?.toString() ?? '').isNotEmpty)
          Text('Contact · ${value['contact_phone']}'),
        Text(
          'Destination · ${value['destination_locality'] ?? ''}, ${value['destination_district'] ?? ''}',
        ),
        const SizedBox(height: 12),
        for (final line
            in (value['items'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>())
          Text(
            '${line['quantity']} × ${line['product_name']} ${line['variant_name'] ?? ''}',
          ),
        const SizedBox(height: 12),
        Text(
          'Status · ${(value['execution_state']?.toString() ?? 'assigned').replaceAll('_', ' ')}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        if (busy) const LinearProgressIndicator(),
        if (value['execution_state'] == 'assigned')
          FilledButton.icon(
            onPressed: busy ? null : () => onTransition('arriving_at_pickup'),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Arrived at pickup'),
          ),
        if (value['execution_state'] == 'arriving_at_pickup')
          FilledButton.icon(
            onPressed: busy ? null : () => onTransition('at_pickup'),
            icon: const Icon(Icons.location_on_outlined),
            label: const Text('I am at the partner'),
          ),
        if (value['execution_state'] == 'at_pickup')
          FilledButton.icon(
            onPressed: busy ? null : onVerifyPickup,
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Verify partner handover'),
          ),
        if (value['execution_state'] == 'picked_up')
          FilledButton.icon(
            onPressed: busy ? null : () => onTransition('en_route'),
            icon: const Icon(Icons.route_outlined),
            label: const Text('Start delivery'),
          ),
        if (value['execution_state'] == 'en_route')
          FilledButton.icon(
            onPressed: busy ? null : onConfirmDelivery,
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Confirm customer handover'),
          ),
        if (value['execution_state'] == 'return_required')
          FilledButton.icon(
            onPressed: busy ? null : () => onTransition('return_in_progress'),
            icon: const Icon(Icons.keyboard_return_rounded),
            label: const Text('Start return to partner'),
          ),
        if (![
          'delivered',
          'returned',
          'cancelled',
          'return_required',
          'return_in_progress',
        ].contains(value['execution_state']))
          OutlinedButton.icon(
            onPressed: busy ? null : onUnableToContinue,
            icon: const Icon(Icons.support_agent_rounded),
            label: const Text('Unable to continue'),
          ),
        if (![
          'delivered',
          'returned',
          'cancelled',
          'return_required',
          'return_in_progress',
        ].contains(value['execution_state']))
          const Text(
            'This report does not release your assignment or transfer custody. Keep the order secure and wait for operations instructions.',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
          ),
        if (![
          'delivered',
          'returned',
          'cancelled',
          'return_required',
          'return_in_progress',
        ].contains(value['execution_state']))
          TextButton.icon(
            onPressed: busy ? null : onException,
            icon: const Icon(Icons.report_problem_outlined),
            label: const Text('Report an issue'),
          ),
        const SizedBox(height: 8),
        const Text(
          'No GPS tracking or delivery ETA is available.',
          style: TextStyle(color: AppTheme.secondaryText),
        ),
      ],
    ),
  );
}

class RiderWorkspaceProfileScreen extends StatefulWidget {
  const RiderWorkspaceProfileScreen({super.key});

  @override
  State<RiderWorkspaceProfileScreen> createState() =>
      _RiderWorkspaceProfileScreenState();
}

class _RiderWorkspaceProfileScreenState
    extends State<RiderWorkspaceProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await apiClient.get('/rider/profile');
      if (mounted) {
        setState(
          () => _profile =
              (response.data as Map<String, dynamic>)['data']
                  as Map<String, dynamic>,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to refresh rider profile.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Rider profile'),
        backgroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  if (_profile != null)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE1E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _profile!['display_name']?.toString() ?? '',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Vehicle type · ${(_profile!['vehicle_type']?.toString() ?? '').replaceAll('_', ' ')}',
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Approved localities',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          for (final place
                              in (_profile!['approved_localities']
                                          as List<dynamic>? ??
                                      [])
                                  .whereType<Map<String, dynamic>>())
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.location_on_outlined),
                              title: Text('${place['name']}'),
                              subtitle: Text('${place['district']}, Odisha'),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  const _PhaseNotice(
                    title: 'Privacy',
                    body: 'Your service locality access is controlled by Grepmind Admin. GPS and delivery availability are not active in this phase.',
                  ),
                ],
              ),
            ),
    );
  }
}

class _PhaseNotice extends StatelessWidget {
  const _PhaseNotice({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE4EAF2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          body,
          style: const TextStyle(color: AppTheme.secondaryText, height: 1.4),
        ),
      ],
    ),
  );
}

class _RiderTextEntryDialog extends StatefulWidget {
  const _RiderTextEntryDialog({
    required this.title,
    required this.label,
    this.numeric = false,
    this.maxLength = 8,
    this.multiline = false,
  });

  final String title;
  final String label;
  final bool numeric;
  final int maxLength;
  final bool multiline;

  @override
  State<_RiderTextEntryDialog> createState() => _RiderTextEntryDialogState();
}

class _RiderTextEntryDialogState extends State<_RiderTextEntryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
      minLines: widget.multiline ? 2 : 1,
      maxLines: widget.multiline ? 4 : 1,
      maxLength: widget.maxLength,
      decoration: InputDecoration(
        labelText: widget.multiline ? null : widget.label,
        hintText: widget.multiline ? widget.label : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: Text(widget.numeric ? 'Verify' : 'Submit'),
      ),
    ],
  );
}
