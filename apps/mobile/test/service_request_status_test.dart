import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/service_request_status_screen.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

void main() {
  final requests = <RequestOptions>[];
  String? reportedStatus;

  setUpAll(() => apiClient.init(baseUrl: 'https://requests.test/api/v1'));
  setUp(() {
    requests.clear();
    reportedStatus = null;
    apiClient.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (options.method == 'GET') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'status': reportedStatus},
                  },
                ),
              );
            } else {
              handler.reject(DioException(requestOptions: options));
            }
          },
        ),
      );
  });

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

  testWidgets('shows customer confirmation action for a proposed new time', (
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
            initialStatus: 'rescheduled',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Time Proposed'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const Key('customer_confirm_reschedule')),
      findsOneWidget,
    );
    expect(find.text('Confirm new time'), findsOneWidget);
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
    expect(
      requests.where((request) => request.method == 'POST').map((r) => r.path),
      ['/requests/#GN-4921/cancel'],
    );
    expect(find.text('Request Cancelled'), findsNothing);
  });

  testWidgets(
    'large text keeps the tracker and cancellation sheet scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const ServiceRequestStatusScreen(
              business: dummyBiz,
              requestId: '00000000-0000-4000-8000-000000000018',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Cancel'), 260);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel Service Request?'), findsOneWidget);

      await tester.ensureVisible(find.text('Keep My Request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep My Request'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel Service Request?'), findsNothing);
      expect(find.text('Request Cancelled'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'declined requests show the closing status without future stages',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ServiceRequestStatusScreen(initialStatus: 'declined'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Request Declined'), findsNWidgets(2));
      expect(find.text('Request Timeline'), findsOneWidget);
      expect(find.text('Current status'), findsOneWidget);
      expect(find.text('Job Completed'), findsNothing);
    },
  );

  testWidgets('polling displays a terminal update and stops at four seconds', (
    tester,
  ) async {
    const id = '00000000-0000-4000-8000-000000000018';
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ServiceRequestStatusScreen(requestId: id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.map((request) => request.path), ['/requests/$id']);

    reportedStatus = 'declined';
    await tester.pump(const Duration(seconds: 3));
    expect(requests, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Request Declined'), findsNWidgets(2));
    expect(requests.map((request) => request.path), [
      '/requests/$id',
      '/requests/$id',
    ]);

    await tester.pump(const Duration(seconds: 8));
    expect(requests, hasLength(2));
  });
}
