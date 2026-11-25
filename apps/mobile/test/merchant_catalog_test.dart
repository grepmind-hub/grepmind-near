import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/merchant_catalog_screen.dart';

void main() {
  testWidgets(
    'MerchantCatalogScreen renders Products and Services tabs cleanly',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MerchantCatalogScreen())),
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
    },
  );

  testWidgets('Tapping Add Product FAB opens bottom sheet modal', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MerchantCatalogScreen())),
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

    // Verify photo buttons and back/close buttons
    expect(find.byKey(const Key('modal_product_back_btn')), findsOneWidget);
    expect(find.byKey(const Key('modal_product_close_btn')), findsOneWidget);
    expect(find.byKey(const Key('btn_pick_camera')), findsOneWidget);
    expect(find.byKey(const Key('btn_pick_gallery')), findsOneWidget);
    expect(find.byKey(const Key('btn_pick_sample')), findsOneWidget);
    expect(find.text('Choose a sample photo'), findsOneWidget);

    // Enter details
    await tester.enterText(
      find.byKey(const Key('modal_product_name')),
      'Organic Herbal Tea 250g',
    );
    await tester.enterText(find.byKey(const Key('modal_product_price')), '350');
    await tester.pump();

    expect(find.text('Organic Herbal Tea 250g'), findsOneWidget);
    expect(find.text('350'), findsOneWidget);

    // Verify tapping close button dismisses the modal
    await tester.tap(find.byKey(const Key('modal_product_close_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Add New Product'), findsNothing);
  });

  testWidgets('Tapping Add Product FAB and then back button dismisses modal', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MerchantCatalogScreen())),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_product_fab')));
    await tester.pumpAndSettle();
    expect(find.text('Add New Product'), findsOneWidget);

    // Tap back button
    await tester.tap(find.byKey(const Key('modal_product_back_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Add New Product'), findsNothing);
  });

  testWidgets('Tapping Add Service FAB on Services tab opens service modal', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MerchantCatalogScreen())),
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
    await tester.enterText(
      find.byKey(const Key('modal_service_name')),
      'Split AC Deep Cleaning',
    );
    await tester.enterText(
      find.byKey(const Key('modal_service_min_price')),
      '750',
    );
    await tester.pump();

    expect(find.text('Split AC Deep Cleaning'), findsOneWidget);
    expect(find.text('750'), findsOneWidget);
  });

  testWidgets(
    'Tapping Choose a sample photo opens category sample photo sheet',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: MerchantCatalogScreen())),
      );

      await tester.pumpAndSettle();

      // Open Add Product modal
      await tester.tap(find.byKey(const Key('add_product_fab')));
      await tester.pumpAndSettle();

      // Verify sample photo button exists and tap it
      expect(find.byKey(const Key('btn_pick_sample')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('btn_pick_sample')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_pick_sample')));
      await tester.pumpAndSettle();

      // Verify category sample grid opens
      expect(find.text('Choose a category photo'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('category_sample_grid')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('category_sample_0')), findsOneWidget);
    },
  );
}
