import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/merchant_registration_screen.dart';

void main() {
  Widget createTestWidget({int initialMode = 0}) {
    return ProviderScope(
      child: MaterialApp(
        home: MerchantRegistrationScreen(initialMode: initialMode),
      ),
    );
  }

  testWidgets('MerchantRegistrationScreen renders wizard and switches steps cleanly', (tester) async {
    await tester.pumpWidget(createTestWidget(initialMode: 0));
    await tester.pumpAndSettle();

    // Verify AppBar & Stepper Header
    expect(find.text('Merchant Onboarding'), findsOneWidget);
    expect(find.text('Register New'), findsOneWidget);
    expect(find.text('Claim Existing'), findsOneWidget);

    // Verify Step 1 content
    expect(find.text('Select Enterprise Classification'), findsOneWidget);
    expect(find.text('Retail Shop & Showroom'), findsOneWidget);
    expect(find.text('Skilled Trade & Professional'), findsOneWidget);
    expect(find.text('Food, Dining & Cafe'), findsOneWidget);
    expect(find.text('Salon, Spa & Wellness'), findsOneWidget);
    expect(find.text('Primary Trade Category'), findsOneWidget);

    // Advance to Step 2
    expect(find.text('Save & Continue'), findsOneWidget);
    await tester.tap(find.text('Save & Continue'));
    await tester.pumpAndSettle();

    // Verify Step 2: Basic & Tax Info
    expect(find.text('Enterprise & Ownership Details'), findsOneWidget);
    expect(find.text('Business / Trade Name *'), findsOneWidget);
    expect(find.text('Owner / Authorized Person *'), findsOneWidget);
    expect(find.text('Tax / Registration ID'), findsOneWidget);

    // Advance to Step 3
    await tester.tap(find.text('Save & Continue'));
    await tester.pumpAndSettle();

    // Verify Step 3: Location & Storefront
    expect(find.text('Storefront Location & Signage'), findsOneWidget);
    expect(find.text('GPS Coordinates Locked'), findsOneWidget);
    expect(find.text('Storefront Signage Photo'), findsOneWidget);

    // Advance to Step 4
    await tester.tap(find.text('Save & Continue'));
    await tester.pumpAndSettle();

    // Verify Step 4: Operations & Summary
    expect(find.text('Operating Mode & Radius'), findsOneWidget);
    expect(find.text('Service & Delivery Coverage'), findsOneWidget);
    expect(find.text('Application Summary'), findsOneWidget);
    expect(find.text('Submit Application'), findsOneWidget);
  });

  testWidgets('MerchantRegistrationScreen Claim Existing listing search and sheet modal', (tester) async {
    await tester.pumpWidget(createTestWidget(initialMode: 1));
    await tester.pumpAndSettle();

    // Verify Claim Tab is active
    expect(find.text('Available for Claim in Bhubaneswar'), findsOneWidget);
    expect(find.text('Maa Tarini Hardware & Sanitary'), findsOneWidget);
    expect(find.text('Shree Ganesh Electricals & Repair'), findsOneWidget);

    // Test Search filter
    await tester.enterText(find.byType(TextField).first, 'Ganesh');
    await tester.pumpAndSettle();

    expect(find.text('Shree Ganesh Electricals & Repair'), findsOneWidget);
    expect(find.text('Maa Tarini Hardware & Sanitary'), findsNothing);

    // Tap Claim Store
    await tester.tap(find.text('Claim Store'));
    await tester.pumpAndSettle();

    // Verify modal verification sheet opened
    expect(find.text('Claim Business Listing'), findsOneWidget);
    expect(find.text('Verify & Claim'), findsOneWidget);
  });

  testWidgets('Switching between Register New and Claim Existing modes works dynamically', (tester) async {
    await tester.pumpWidget(createTestWidget(initialMode: 0));
    await tester.pumpAndSettle();

    expect(find.text('Select Enterprise Classification'), findsOneWidget);

    // Tap Claim Existing in segmented control
    await tester.tap(find.text('Claim Existing'));
    await tester.pumpAndSettle();

    expect(find.text('Available for Claim in Bhubaneswar'), findsOneWidget);
    expect(find.text('Maa Tarini Hardware & Sanitary'), findsOneWidget);

    // Tap Register New
    await tester.tap(find.text('Register New'));
    await tester.pumpAndSettle();

    expect(find.text('Select Enterprise Classification'), findsOneWidget);
  });

  testWidgets('Selecting business models (Enterprise Classifications) updates selection cleanly', (tester) async {
    await tester.pumpWidget(createTestWidget(initialMode: 0));
    await tester.pumpAndSettle();

    // Default selection is Retail Shop & Showroom
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Tap Skilled Trade & Professional
    final proFinder = find.byKey(const ValueKey('enterprise_type_service_pro'));
    await tester.ensureVisible(proFinder);
    await tester.tap(proFinder);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Tap Food, Dining & Cafe
    final foodFinder = find.byKey(const ValueKey('enterprise_type_food'));
    await tester.ensureVisible(foodFinder);
    await tester.tap(foodFinder);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Tap Salon, Spa & Wellness
    final wellnessFinder = find.byKey(const ValueKey('enterprise_type_wellness'));
    await tester.ensureVisible(wellnessFinder);
    await tester.tap(wellnessFinder);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Tap Retail Shop & Showroom again
    final retailFinder = find.byKey(const ValueKey('enterprise_type_retail'));
    await tester.ensureVisible(retailFinder);
    await tester.tap(retailFinder);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}

