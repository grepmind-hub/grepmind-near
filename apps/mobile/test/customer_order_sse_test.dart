import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/customer_order_sse.dart';

void main() {
  test(
    'SSE parser preserves event IDs and multi-line data, ignoring heartbeats',
    () async {
      final events = await parseServerSentEvents(
        Stream<String>.fromIterable([
          ': ping 123',
          'id: evt-1',
          'event: delivery.status',
          'data: {"payload":',
          'data: {"order_id":"order-1"}}',
          '',
        ]),
      ).toList();

      expect(events, hasLength(1));
      expect(events.single.event, 'delivery.status');
      expect(events.single.id, 'evt-1');
      expect(events.single.data, '{"payload":\n{"order_id":"order-1"}}');
    },
  );

  test('order event gate rejects foreign scopes and duplicate IDs', () {
    final gate = CustomerOrderEventGate('order-1');
    const own = ServerSentEvent(
      event: 'delivery.status',
      id: 'evt-1',
      data: '{"payload":{"order_id":"order-1"}}',
    );
    const foreign = ServerSentEvent(
      event: 'delivery.status',
      id: 'evt-2',
      data: '{"payload":{"order_id":"order-2"}}',
    );

    expect(gate.shouldReconcile(foreign), isFalse);
    expect(gate.shouldReconcile(own), isTrue);
    expect(gate.shouldReconcile(own), isFalse);
  });

  test('out-of-order order events only request canonical reconciliation', () {
    final gate = CustomerOrderEventGate('order-1');
    const delivered = ServerSentEvent(
      event: 'delivery.delivered',
      id: 'evt-delivered',
      data: '{"payload":{"order_id":"order-1"}}',
    );
    const preparing = ServerSentEvent(
      event: 'order.status',
      id: 'evt-preparing',
      data: '{"payload":{"order_id":"order-1","status":"preparing"}}',
    );

    // Arrival order does not mutate local status. Both frames trigger an exact
    // order API read, whose server state determines what the screen renders.
    expect(gate.shouldReconcile(delivered), isTrue);
    expect(gate.shouldReconcile(preparing), isTrue);
  });

  test('connected handshake triggers authoritative recovery', () {
    final gate = CustomerOrderEventGate('order-1');
    const connected = ServerSentEvent(
      event: 'connected',
      data: '{"status":"connected"}',
    );
    expect(gate.shouldReconcile(connected), isTrue);
  });
}
