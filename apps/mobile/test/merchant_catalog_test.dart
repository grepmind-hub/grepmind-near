import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/merchant_catalog_screen.dart';

void main() {
  testWidgets('MerchantCatalogScreen renders Products and Services tabs cleanly', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MerchantCatalogScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Search
    expect(find.text('Catalog Management'), findsOneWidget);
    expect(find.byKey(const Key('search_catalog_input')), findsOneWidget);

    // Verify TabBar
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);

    // Verify Product FAB
    expect(find.byKey(const Key('add_product_fab')), findsOneWidget);

    // Switch to Services tab
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    // Verify Service FAB is now shown
    expect(find.byKey(const Key('add_service_fab')), findsOneWidget);
  });

  testWidgets('Tapping Add Product FAB opens bottom sheet modal', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MerchantCatalogScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Add Product FAB
    await tester.tap(find.byKey(const Key('add_product_fab')));
    await tester.pumpAndSettle();

    // Verify modal fields
    expect(find.text('Add New Product'), findsOneWidget);
    expect(find.byKey(const Key('modal_product_name')), findsOneWidget);
    expect(find.byKey(const Key('modal_product_price')), findsOneWidget);
    expect(find.byKey(const Key('save_product_btn')), findsOneWidget);

    // Enter details
    await tester.enterText(find.byKey(const Key('modal_product_name')), 'Organic Herbal Tea 250g');
    await tester.enterText(find.byKey(const Key('modal_product_price')), '350');
    await tester.pump();

    expect(find.text('Organic Herbal Tea 250g'), findsOneWidget);
    expect(find.text('350'), findsOneWidget);
  });

  testWidgets('Tapping Add Service FAB on Services tab opens service modal', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MerchantCatalogScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Switch to Services tab
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    // Tap Add Service FAB
    await tester.tap(find.byKey(const Key('add_service_fab')));
    await tester.pumpAndSettle();

    // Verify modal fields
    expect(find.text('Add New Service'), findsOneWidget);
    expect(find.byKey(const Key('modal_service_name')), findsOneWidget);
    expect(find.byKey(const Key('modal_service_min_price')), findsOneWidget);
    expect(find.byKey(const Key('save_service_btn')), findsOneWidget);

    // Enter service details
    await tester.enterText(find.byKey(const Key('modal_service_name')), 'Split AC Deep Cleaning');
    await tester.enterText(find.byKey(const Key('modal_service_min_price')), '750');
    await tester.pump();

    expect(find.text('Split AC Deep Cleaning'), findsOneWidget);
    expect(find.text('750'), findsOneWidget);
  });
}
