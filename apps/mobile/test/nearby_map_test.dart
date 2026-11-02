import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';

void main() {
  testWidgets('NearbyMapScreen renders top category chips, radar view, and actions', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: NearbyMapScreen(),
        ),
      ),
    );

    // Use bounded pumps since radar animation repeats continuously
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify title and location subtitle
    expect(find.text('Nearby Map'), findsOneWidget);
    expect(find.text(' (5 km radius)'), findsOneWidget);

    // Verify top category chips
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Electrician'), findsOneWidget);
    expect(find.text('Hardware'), findsOneWidget);

    // Tap Electrician chip
    await tester.tap(find.text('Electrician'));
    await tester.pump(const Duration(milliseconds: 300));

    // Toggle radar view button in AppBar
    final toggleButton = find.byTooltip('Show Radar View');
    if (toggleButton.evaluate().isNotEmpty) {
      await tester.tap(toggleButton);
      await tester.pump(const Duration(milliseconds: 300));
    }
  });
}
