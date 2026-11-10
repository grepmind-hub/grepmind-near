import 'dart:convert';

class ServerSentEvent {
  const ServerSentEvent({required this.event, required this.data, this.id});

  final String event;
  final String data;
  final String? id;
}

Stream<ServerSentEvent> parseServerSentEvents(Stream<String> lines) async* {
  var eventName = 'message';
  String? eventId;
  final data = <String>[];

  ServerSentEvent? finishEvent() {
    if (data.isEmpty) return null;
    final event = ServerSentEvent(
      event: eventName,
      data: data.join('\n'),
      id: eventId,
    );
    eventName = 'message';
    eventId = null;
    data.clear();
    return event;
  }

  await for (final line in lines) {
    if (line.isEmpty) {
      final event = finishEvent();
      if (event != null) yield event;
      eventName = 'message';
      eventId = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;

    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        eventName = value;
        break;
      case 'data':
        data.add(value);
        break;
      case 'id':
        if (!value.contains('\u0000')) eventId = value;
        break;
    }
  }

  final event = finishEvent();
  if (event != null) yield event;
}

/// Accepts only events for the displayed order and deduplicates retry/replay
/// frames. Callers always fetch canonical state instead of applying event order.
class CustomerOrderEventGate {
  CustomerOrderEventGate(this.orderId);

  final String orderId;
  final Set<String> _seenIds = <String>{};
  final List<String> _idOrder = <String>[];
  static const _maxRememberedIds = 128;

  bool shouldReconcile(ServerSentEvent event) {
    if (event.event == 'connected') return true;
    if (event.event != 'order.status' && !event.event.startsWith('delivery.')) {
      return false;
    }
    try {
      final decoded = event.data;
      final payload = _payloadFromEvent(decoded);
      if (payload['order_id'] != orderId) return false;
      final id = event.id;
      if (id == null || id.isEmpty) return true;
      if (!_seenIds.add(id)) return false;
      _idOrder.add(id);
      if (_idOrder.length > _maxRememberedIds) {
        _seenIds.remove(_idOrder.removeAt(0));
      }
      return true;
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  Map<String, dynamic> _payloadFromEvent(String data) {
    final event = _decodeObject(data);
    final payload = event['payload'];
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) return Map<String, dynamic>.from(payload);
    return const {};
  }

  Map<String, dynamic> _decodeObject(String data) {
    return Map<String, dynamic>.from(jsonDecode(data) as Map);
  }
}
