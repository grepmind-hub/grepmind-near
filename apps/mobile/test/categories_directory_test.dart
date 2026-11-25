import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/screens/categories_screen.dart';

void main() {
  testWidgets(
    'CategoriesScreen displays 19 categories with section filters and listings tab',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: CategoriesScreen())),
      );

      // Initial load
      await tester.pumpAndSettle();

      // Verify Title and 19 Categories count badge
      expect(find.text('Categories Directory'), findsOneWidget);
      expect(find.text('19 Categories'), findsOneWidget);

      // Verify Tab 1 (Categories) is active
      expect(find.text('Categories (19)'), findsOneWidget);
      expect(find.text('Explore Listings (57)'), findsOneWidget);

      // Verify key categories are present in the taxonomy
      expect(find.text('Grocery & Kirana'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Pharmacy & Health'), findsOneWidget);

      // Verify distance and pincode badges are shown on category cards
      expect(find.textContaining('751007'), findsWidgets);
      expect(find.textContaining('km'), findsWidgets);

      // Verify category cards render correctly
      expect(find.text('Grocery & Kirana'), findsOneWidget);
      expect(find.text('Hardware & Tools'), findsOneWidget);
      expect(find.text('Electrician'), findsOneWidget);
      expect(find.text('Hotels & Lodging'), findsOneWidget);

      // Test Search input filters categories
      await tester.enterText(find.byType(TextField), 'Mobile');
      await tester.pumpAndSettle();

      expect(find.text('Electronics & Mobile'), findsOneWidget);
      expect(find.text('Grocery & Kirana'), findsNothing);
    },
  );
}
