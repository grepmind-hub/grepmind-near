import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/service_request_status_screen.dart';
import 'package:grepmind_mobile/core/models/business.dart';

void main() {
  const dummyBiz = Business(
    id: '77777777-7777-7777-7777-777777777777',
    name: 'Ramesh Kumar - Electrical Services',
    categorySlug: 'electrician',
    status: 'approved',
    verificationStatus: 'verified',
    addressText: 'Plot 42, Saheed Nagar',
    locality: 'Saheed Nagar',
    city: 'Cuttack',
    phoneE164: '+919876543220',
  );

  testWidgets('ServiceRequestStatusScreen renders all sections cleanly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ServiceRequestStatusScreen(
            business: dummyBiz,
            requestId: '#GN-4921',
            initialStatus: 'requested',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify AppBar and Header
    expect(find.text('Service Request Status'), findsOneWidget);
    expect(find.text('Booking ID #GN-4921'), findsOneWidget);

    // Verify Hero Status Card and Timeline Stepper
    expect(find.text('Live Progress Timeline'), findsOneWidget);
    expect(find.text('Request Submitted'), findsAtLeastNWidgets(1));
    expect(find.text('Provider Accepted'), findsOneWidget);
    // Scroll down to reveal Assigned Pro and Receipt
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    // Verify Assigned Pro Card
    expect(find.text('Assigned Professional'), findsOneWidget);
    expect(find.text('Ramesh Kumar - Electrical Services'), findsOneWidget);
    expect(find.text('Call Pro'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);

    // Verify Receipt Summary
    expect(find.text('Job & Receipt Summary'), findsOneWidget);
    expect(find.text('Indicative Estimate'), findsOneWidget);

    // Verify Bottom Actions
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Back to Explore'), findsOneWidget);
  });

  testWidgets('does not expose client-side request stage controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ServiceRequestStatusScreen(
            business: dummyBiz,
            requestId: '#GN-4921',
            initialStatus: 'requested',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Accepted'), findsNothing);
    expect(find.text('Progress'), findsNothing);
  });

  testWidgets('Cancel flow opens cancellation modal and allows selection', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ServiceRequestStatusScreen(
            business: dummyBiz,
            requestId: '#GN-4921',
            initialStatus: 'requested',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Cancel button
    final cancelButton = find.text('Cancel');
    expect(cancelButton, findsOneWidget);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    // Verify modal appeared
    expect(find.text('Cancel Service Request?'), findsOneWidget);
    expect(find.text('Please tell us the reason:'), findsOneWidget);
    expect(find.text('Found another skilled professional'), findsOneWidget);

    // Select reason
    await tester.tap(find.text('Found another skilled professional'));
    await tester.pumpAndSettle();

    // A failed API call must not fabricate a cancelled state.
    expect(find.text('Request Cancelled'), findsNothing);
  });
}
