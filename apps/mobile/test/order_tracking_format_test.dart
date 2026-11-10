import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';

void main() {
  test('delivery timeline timestamps use a concise human-readable format', () {
    expect(
      formatOrderTrackingTimestamp(DateTime(2026, 11, 7, 21, 16)),
      '7 Nov, 9:16 PM',
    );
  });

  test('terminal execution state wins after assignment is released', () {
    expect(resolveCustomerDeliveryState('delivered', 'assigned'), 'delivered');
  });

  test('dispatch state is used before rider execution starts', () {
    expect(
      resolveCustomerDeliveryState('not_started', 'pending_dispatch'),
      'pending_dispatch',
    );
  });

  test('active rider execution state takes precedence over dispatch state', () {
    expect(resolveCustomerDeliveryState('en_route', 'assigned'), 'en_route');
  });

  test('completed delivery remains visible after assignment is closed', () {
    expect(
      customerDeliveryDispatchMessage(
        state: 'assigned',
        riderAssigned: false,
        executionState: 'delivered',
      ),
      'Delivery completed. The rider assignment is closed.',
    );
  });
}
