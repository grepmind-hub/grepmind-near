import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/merchant_hours_coverage_screen.dart';

void main() {
  testWidgets('MerchantHoursCoverageScreen renders Operating Hours tab cleanly', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MerchantHoursCoverageScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Subtitle
    expect(find.text('Hours & Coverage'), findsOneWidget);

    // Verify Tabs
    expect(find.text('Operating Hours'), findsOneWidget);
    expect(find.text('Service Coverage'), findsOneWidget);

    // Verify Quick Actions
    expect(find.text('Mon \u2192 Mon-Fri'), findsOneWidget);
    expect(find.text('All Open'), findsOneWidget);
    expect(find.text('All Closed'), findsOneWidget);

    // Verify Days rendered (Monday, Tuesday, etc.)
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Friday'), findsOneWidget);
    expect(find.text('Sunday'), findsOneWidget);

    // Verify Save Button
    expect(find.text('Save Operating Hours'), findsOneWidget);
  });

  testWidgets('Operating Hours quick action All Closed and All Open toggle day states', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MerchantHoursCoverageScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap All Closed
    await tester.tap(find.text('All Closed'));
    await tester.pumpAndSettle();

    // All days should show 'Closed all day'
    expect(find.text('Closed all day'), findsNWidgets(7));

    // Tap All Open
    await tester.tap(find.text('All Open'));
    await tester.pumpAndSettle();

    // All days should show 'Open for business'
    expect(find.text('Open for business'), findsNWidgets(7));
  });

  testWidgets('Service Coverage tab displays radius slider, chips, and localities', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MerchantHoursCoverageScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Switch to Service Coverage tab
    await tester.tap(find.text('Service Coverage'));
    await tester.pumpAndSettle();

    // Verify Hub & Radius
    expect(find.text('Base Service Hub'), findsOneWidget);
    expect(find.text('Service Radius'), findsOneWidget);
    expect(find.text('Coverage Localities'), findsOneWidget);
    expect(find.text('Accept Immediate Bookings'), findsOneWidget);

    // Verify Preset Radius chips
    expect(find.text('2 km'), findsOneWidget);
    expect(find.text('5 km'), findsOneWidget);
    expect(find.text('10 km'), findsOneWidget);
    expect(find.text('15 km'), findsOneWidget);
    expect(find.text('25 km'), findsOneWidget);

    // Verify Save Button
    expect(find.text('Save Coverage Settings'), findsOneWidget);
  });
}
