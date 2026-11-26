part of '../order_tracking_screen.dart';

IconData _iconForTimelineStep(String label) {
  final l = label.toLowerCase();
  if (l.contains('placed')) return Icons.shopping_bag_outlined;
  if (l.contains('accept')) return Icons.storefront_outlined;
  if (l.contains('prepar')) return Icons.soup_kitchen_outlined;
  if (l.contains('ready') ||
      l.contains('pickup verified') ||
      l.contains('handover')) {
    return Icons.inventory_2_outlined;
  }
  if (l.contains('heading') || l.contains('arrived at partner')) {
    return Icons.store_outlined;
  }
  if (l.contains('rider') || l.contains('assign')) {
    return Icons.two_wheeler_outlined;
  }
  if (l.contains('way') || l.contains('en route') || l.contains('picked up')) {
    return Icons.delivery_dining_outlined;
  }
  if (l.contains('delivered') || l.contains('completed')) {
    return Icons.check_circle_outline_rounded;
  }
  if (l.contains('issue') ||
      l.contains('cancel') ||
      l.contains('fail') ||
      l.contains('rejected') ||
      l.contains('unreachable')) {
    return Icons.error_outline_rounded;
  }
  return Icons.check_rounded;
}

class _TimelineStepItem extends StatelessWidget {
  const _TimelineStepItem({
    required this.title,
    required this.subtitle,
    this.detail,
    required this.isFirst,
    required this.isLast,
    required this.isCompleted,
    required this.isActive,
    this.icon,
  });

  final String title;
  final String subtitle;
  final String? detail;
  final bool isFirst;
  final bool isLast;
  final bool isCompleted;
  final bool isActive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vertical connector line and circular node
          SizedBox(
            width: 32,
            child: Column(
              children: [
                // Top line
                Container(
                  width: 2.5,
                  height: 6,
                  color: isFirst
                      ? Colors.transparent
                      : (isCompleted || isActive
                            ? AbashyakaColors.success
                            : AbashyakaColors.softGrey),
                ),
                // Indicator Node
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AbashyakaColors.success
                        : isCompleted
                        ? AbashyakaColors.successSurface
                        : AbashyakaColors.pearlWhite,
                    border: Border.all(
                      color: isActive
                          ? AbashyakaColors.success
                          : isCompleted
                          ? AbashyakaColors.success
                          : AbashyakaColors.aquaSilverBorder,
                      width: isActive ? 2.5 : 1.5,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AbashyakaColors.success
                                  .withValues(alpha: 0.3),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Icon(
                      icon ??
                          (isCompleted || isActive
                              ? Icons.check_rounded
                              : Icons.circle),
                      size: icon != null
                          ? 13
                          : (isCompleted || isActive ? 14 : 6),
                      color: isActive
                          ? AbashyakaColors.pureWhite
                          : isCompleted
                          ? AbashyakaColors.success
                          : AbashyakaColors.disabledText,
                    ),
                  ),
                ),
                // Bottom connecting vertical line
                Expanded(
                  child: isLast
                      ? const SizedBox.shrink()
                      : Container(
                          width: 2.5,
                          color: isCompleted
                              ? AbashyakaColors.success
                              : AbashyakaColors.softGrey,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isActive
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: isActive
                                ? const Color(0xFF065F46)
                                : AbashyakaColors.primaryText,
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AbashyakaColors.successSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AbashyakaColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AbashyakaColors.mutedText,
                    ),
                  ),
                  if (detail != null && detail!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedOrderTimeline extends StatelessWidget {
  const _UnifiedOrderTimeline({
    required this.order,
    required this.state,
    required this.events,
    required this.error,
  });
  final CustomerOrder order;
  final String? state;
  final List<Map<String, dynamic>> events;
  final String? error;

  static const _deliveryLabels = <String, String>{
    'pending_dispatch': 'Finding an available rider',
    'offered': 'Rider offer sent',
    'no_rider_available': 'No rider available yet',
    'placed': 'Order placed',
    'accepted': 'Partner accepted',
    'preparing': 'Partner is preparing',
    'ready_for_pickup': 'Ready for pickup',
    'assigned': 'Rider assigned',
    'rider_assigned': 'Rider assigned',
    'arriving_at_pickup': 'Rider heading to partner',
    'at_pickup': 'Rider arrived at partner',
    'pickup_verified': 'Partner handover verified',
    'picked_up': 'Order picked up',
    'en_route': 'On the way to you',
    'customer_otp_verified': 'Delivered with your confirmation',
    'delivered': 'Delivered',
    'pickup_failed': 'Pickup issue reported',
    'customer_unreachable': 'Rider could not reach you',
    'delivery_failed': 'Delivery issue reported',
    'return_required': 'Return requested',
    'return_in_progress': 'Returning to partner',
    'returned': 'Returned to partner',
    'cancelled': 'Delivery cancelled',
    'resolved': 'Delivery issue resolved',
  };

  List<_TimelineEntry> _entries() {
    final result = <_TimelineEntry>[
      for (final event in events)
        _TimelineEntry(
          title: _timelineLabel(event),
          at:
              DateTime.tryParse(event['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return result;
  }

  String _timelineLabel(Map<String, dynamic> event) {
    final eventType = event['event_type']?.toString();
    final state = event['to_state']?.toString();
    if (eventType == 'order_status') {
      return _deliveryLabels[state] ?? 'Order updated';
    }
    return _deliveryLabels[eventType] ??
        _deliveryLabels[state] ??
        (eventType?.replaceAll('_', ' ') ?? 'Delivery update');
  }

  bool get _isOrderTerminal =>
      order.status == OrderStatus.delivered ||
      order.status == OrderStatus.completed ||
      order.status == OrderStatus.cancelled ||
      order.status == OrderStatus.rejected;

  @override
  Widget build(BuildContext context) {
    final timelineEntries = _entries();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AbashyakaColors.successSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Icon(
                  Icons.alt_route_rounded,
                  size: 18,
                  color: AbashyakaColors.success,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Order and delivery timeline',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AbashyakaColors.primaryText,
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          if (timelineEntries.isEmpty && error == null)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Order updates will appear here as the partner and rider progress.',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
              ),
            )
          else ...[
            const SizedBox(height: 14),
            for (var i = 0; i < timelineEntries.length; i++)
              _TimelineStepItem(
                title: timelineEntries[i].title,
                subtitle: formatOrderTrackingTimestamp(timelineEntries[i].at),
                isFirst: i == 0,
                isLast: i == timelineEntries.length - 1,
                isCompleted: i < timelineEntries.length - 1 || _isOrderTerminal,
                isActive: i == timelineEntries.length - 1 && !_isOrderTerminal,
                icon: _iconForTimelineStep(timelineEntries[i].title),
              ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AbashyakaColors.pearlWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AbashyakaColors.softGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state != null) ...[
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AbashyakaColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Current delivery state · ${_deliveryLabels[state] ?? state!.replaceAll('_', ' ')}',
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                const Text(
                  'No live location or estimated arrival time is shown.',
                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEntry {
  const _TimelineEntry({required this.title, required this.at});
  final String title;
  final DateTime at;
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.order});
  final CustomerOrder order;
  @override
  Widget build(BuildContext context) {
    final events = order.statusEvents;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AbashyakaColors.successSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: AbashyakaColors.success,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Status history',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AbashyakaColors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (events.isEmpty)
            const Text(
              'No status history is available for this order yet.',
              style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
            )
          else
            for (var i = 0; i < events.length; i++)
              _TimelineStepItem(
                title: events[i].status.statusLabel,
                subtitle: events[i].eventKind == 'history_snapshot'
                    ? 'Earlier status history was not recorded for this order.'
                    : formatOrderTrackingTimestamp(events[i].createdAt),
                detail: events[i].reason?.isNotEmpty == true
                    ? events[i].reason
                    : null,
                isFirst: i == 0,
                isLast: i == events.length - 1,
                isCompleted:
                    i < events.length - 1 ||
                    events[i].status == OrderStatus.delivered,
                isActive:
                    i == events.length - 1 &&
                    events[i].status != OrderStatus.delivered,
                icon: _iconForTimelineStep(events[i].status.statusLabel),
              ),
        ],
      ),
    );
  }
}
