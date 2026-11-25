import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/screens/categories_screen.dart';

void main() {
  testWidgets(
    'CategoriesScreen displays 18 categories, admin service places, and no raw pincodes',
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

      // Verify Title and 18 Categories count badge
      expect(find.text('Categories Directory'), findsOneWidget);
      expect(find.text('18 Categories'), findsOneWidget);

      // Verify Tab 1 (Categories) is active
      expect(find.text('Categories (18)'), findsOneWidget);
      expect(find.text('Explore Listings (43)'), findsOneWidget);

      // Verify key categories are present in the taxonomy
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Grocery & Kirana'), findsOneWidget);
      expect(find.text('Medicines & Pharmacy'), findsOneWidget);
      expect(find.text('Services'), findsOneWidget);
      expect(find.text('Shops & Retail'), findsOneWidget);
      expect(find.text('Cab & Auto'), findsOneWidget);

      // Verify distance and service places are shown on category cards (NO raw pincodes)
      expect(find.textContaining('751007'), findsNothing);
      expect(find.textContaining('754022'), findsNothing);
      expect(find.textContaining('Chhatia'), findsWidgets);
      expect(find.textContaining('km'), findsWidgets);

      // Test Search input filters categories
      await tester.enterText(find.byType(TextField), 'Mobile');
      await tester.pumpAndSettle();

      expect(find.text('Electronics & Mobile'), findsOneWidget);
      expect(find.text('Grocery & Kirana'), findsNothing);
    },
  );
}
