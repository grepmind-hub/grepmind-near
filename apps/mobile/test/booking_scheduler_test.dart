import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/booking_scheduler_screen.dart';
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
    city: 'Bhubaneswar',
  );

  testWidgets('BookingSchedulerScreen renders all sections cleanly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: BookingSchedulerScreen(
            business: dummyBiz,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify header and sections
    expect(find.text('Schedule Ramesh'), findsOneWidget);
    expect(find.text('Ramesh Kumar - Electrical Services'), findsOneWidget);
    expect(find.text('₹299/hr'), findsOneWidget);
    expect(find.text('Job Scope & Duration'), findsOneWidget);
    expect(find.text('Select a Date'), findsOneWidget);
    expect(find.text('Available Time Slots'), findsOneWidget);
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Afternoon'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Job Details & Address'), findsOneWidget);
    expect(find.text('Book Ramesh'), findsOneWidget);
  });

  testWidgets('Interactive slot selection and booking confirmation flow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: BookingSchedulerScreen(
            business: dummyBiz,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Select afternoon slot 01:00 PM
    final slotFinder = find.text('01:00 PM');
    expect(slotFinder, findsOneWidget);
    await tester.ensureVisible(slotFinder);
    await tester.tap(slotFinder);
    await tester.pumpAndSettle();

    // Tap Book Ramesh CTA
    final bookButton = find.text('Book Ramesh');
    expect(bookButton, findsOneWidget);
    await tester.tap(bookButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // Verify confirmation modal bottom sheet
    expect(find.text('Booking Requested!'), findsOneWidget);
    expect(find.text('Ramesh Kumar - Electrical Services'), findsAtLeastNWidgets(1));
    expect(find.text('Done & Return to Pro'), findsOneWidget);
  });
}
