import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/booking_scheduler_screen.dart';
import 'package:grepmind_mobile/core/models/business.dart';

void main() {
  setUpAll(() {
    apiClient.init();
    apiClient.dio.interceptors.clear();
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 201,
              data: {
                'data': {'id': '12345678-1234-1234-1234-123456789012'},
              },
            ),
          );
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
  );

  testWidgets('BookingSchedulerScreen renders all sections cleanly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: BookingSchedulerScreen(business: dummyBiz)),
      ),
    );

    await tester.pumpAndSettle();

    // Verify header and sections
    expect(find.text('Schedule Ramesh'), findsOneWidget);
    expect(find.text('Ramesh Kumar - Electrical Services'), findsOneWidget);
    expect(find.text('Rate not published'), findsOneWidget);
    expect(find.text('Job Scope & Duration'), findsOneWidget);
    expect(find.text('Select a Date'), findsOneWidget);
    expect(find.text('Available Time Slots'), findsOneWidget);
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Afternoon'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Job Details & Address'), findsOneWidget);
    expect(find.text('Book now'), findsOneWidget);
  });

  testWidgets('booking action fits a narrow screen with a long business name', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: BookingSchedulerScreen(
            business: dummyBiz,
            businessName:
                'Generated Cuttack Business With A Very Long Validation Name',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Book now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not fabricate appointment slots when API has none', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: BookingSchedulerScreen(business: dummyBiz)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('01:00 PM'), findsNothing);
    expect(find.text('Booking Requested!'), findsNothing);
  });
}
