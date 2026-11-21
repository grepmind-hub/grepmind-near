import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/notifications/notification_permission.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

class NotificationPermissionCard extends StatefulWidget {
  const NotificationPermissionCard({super.key});

  @override
  State<NotificationPermissionCard> createState() =>
      _NotificationPermissionCardState();
}

class _NotificationPermissionCardState extends State<NotificationPermissionCard>
    with WidgetsBindingObserver {
  final _manager = NotificationPermissionManager(
    AndroidNotificationPermissionGateway(),
  );
  NotificationPermissionState? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await _manager.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _act() async {
    setState(() => _busy = true);
    final current = _status;
    if (current == NotificationPermissionState.denied) {
      final opened = await _manager.openSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open settings. Please open Android app settings.',
            ),
          ),
        );
      }
    } else {
      final result = await _manager.requestOnce();
      if (mounted) setState(() => _status = result);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_status) {
      null => 'Checking device notification permission…',
      NotificationPermissionState.allowed =>
        'Device notifications are allowed.',
      NotificationPermissionState.notRequested =>
        'Device notifications are not enabled yet.',
      NotificationPermissionState.denied => 'Device notifications are off. You can enable them in Android settings.',
      NotificationPermissionState.unavailable =>
        'Device notification permission is unavailable.',
    };
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Device notifications',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Allow notifications to receive order, delivery and account updates when push delivery is available.',
          ),
          const SizedBox(height: 8),
          Text(label),
          if (_status == NotificationPermissionState.notRequested ||
              _status == NotificationPermissionState.denied) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _act,
              child: Text(
                _status == NotificationPermissionState.denied
                    ? 'Open settings'
                    : 'Enable notifications',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
