import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/merchant_registration_screen.dart';

class _ClaimApiAdapter implements HttpClientAdapter {
  bool submitted = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.endsWith('/merchant/business-claims')) {
      return _jsonResponse({
        'data': submitted
            ? [
                {
                  'id': 'claim-request-id',
                  'business_id': 'business-id',
                  'business_name': 'Hardware Test Listing',
                  'city': 'Cuttack',
                  'status': 'pending',
                  'created_at': '2026-11-04T00:00:00Z',
                },
              ]
            : [],
      });
    }
    if (path.endsWith('/merchant/claimable-businesses')) {
      return _jsonResponse({
        'data': [
          {
            'id': 'business-id',
            'name': 'Hardware Test Listing',
            'category_slug': 'hardware',
            'category': 'Hardware',
            'locality': 'Badambadi',
            'city': 'Cuttack',
          },
          {
            'business_id': 'legacy-business-id',
            'business_name': 'Jajpur Hardware Listing',
            'category_slug': 'hardware',
            'locality': 'Town Centre',
            'city': 'Jajpur',
          },
        ],
      });
    }
    if (path.endsWith('/merchant/businesses/business-id/claim')) {
      submitted = true;
      return _jsonResponse({
        'data': {'id': 'claim-request-id', 'status': 'pending'},
      }, status: 201);
    }
    return _jsonResponse({'data': []});
  }

  ResponseBody _jsonResponse(Object value, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(value),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  Widget createTestWidget({int initialMode = 0}) {
    return ProviderScope(
      child: MaterialApp(
        home: MerchantRegistrationScreen(initialMode: initialMode),
      ),
    );
  }

  testWidgets(
    'MerchantRegistrationScreen renders wizard and switches steps cleanly',
    (tester) async {
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
      expect(find.text('Primary business category'), findsOneWidget);

      // Advance to Step 2
      expect(find.text('Save & Continue'), findsOneWidget);
      await tester.tap(find.text('Save & Continue'));
      await tester.pumpAndSettle();

      // Verify Step 2: Basic & Tax Info
      expect(find.text('Enterprise & Ownership Details'), findsOneWidget);
      expect(find.text('Business / Trade Name *'), findsOneWidget);
      expect(find.text('Owner / Authorized Person *'), findsOneWidget);
      expect(find.text('Tax / Registration ID'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('merchant_business_name')),
        'Test Merchant Shop',
      );
      await tester.enterText(
        find.byKey(const ValueKey('merchant_owner_name')),
        'Test Owner',
      );

      // Advance to Step 3
      await tester.tap(find.text('Save & Continue'));
      await tester.pumpAndSettle();

      // Verify Step 3: Location & Storefront
      expect(find.text('Storefront Location & Signage'), findsOneWidget);
      expect(find.text('Business location not set'), findsOneWidget);
      expect(find.text('Storefront Signage Photo'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('merchant_address')),
        '12 Market Road',
      );
      await tester.enterText(
        find.byKey(const ValueKey('merchant_locality')),
        'Badambadi',
      );
      await tester.enterText(
        find.byKey(const ValueKey('merchant_city')),
        'Cuttack',
      );
      await tester.enterText(
        find.byKey(const ValueKey('merchant_postal_code')),
        '753012',
      );
      final coordinatesExpander = find.text('Enter map coordinates manually');
      await tester.ensureVisible(coordinatesExpander);
      await tester.tap(coordinatesExpander);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('merchant_latitude')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('merchant_latitude')),
        '20.4625',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('merchant_longitude')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('merchant_longitude')),
        '85.8828',
      );

      // Advance to Step 4
      await tester.tap(find.text('Save & Continue'));
      await tester.pumpAndSettle();

      // Verify Step 4: Operations & Summary
      expect(find.text('Operating Mode & Radius'), findsOneWidget);
      expect(find.text('Service & Delivery Coverage'), findsOneWidget);
      expect(find.text('Application Summary'), findsOneWidget);
      expect(find.text('Submit Application'), findsOneWidget);
    },
  );

  testWidgets(
    'Claim Existing requires live listing search and does not expose fixtures',
    (tester) async {
      await tester.pumpWidget(createTestWidget(initialMode: 1));
      await tester.pumpAndSettle();

      // Claim search starts empty and explains the server-backed review process.
      expect(find.text('Available listings for claim'), findsOneWidget);
      expect(
        find.text('Enter at least 2 characters to search approved listings.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'ownership changes only after an administrator verifies the claim.',
        ),
        findsOneWidget,
      );
      expect(find.text('Maa Tarini Hardware & Sanitary'), findsNothing);
      expect(find.text('Shree Ganesh Electricals & Repair'), findsNothing);

      // Test Search filter
      await tester.enterText(find.byType(TextField).first, 'Ganesh');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // API failures remain explicit and do not fall back to fixtures.
      expect(
        find.text(
          'Could not search listings. Check your connection and retry.',
        ),
        findsOneWidget,
      );
      expect(find.text('Shree Ganesh Electricals & Repair'), findsNothing);
      expect(find.text('Maa Tarini Hardware & Sanitary'), findsNothing);

      // Removed sample listings cannot expose a fabricated claim action.
      expect(find.text('Request review'), findsNothing);
    },
  );

  testWidgets(
    'Claim search renders API listings and submits a pending request',
    (tester) async {
      final adapter = _ClaimApiAdapter();
      apiClient.init(baseUrl: 'https://claims.test/api/v1');
      apiClient.dio.interceptors.clear();
      apiClient.dio.httpClientAdapter = adapter;

      await tester.pumpWidget(createTestWidget(initialMode: 1));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'hardware');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Hardware Test Listing'), findsOneWidget);
      expect(find.text('Approved listing · Cuttack'), findsOneWidget);
      expect(find.text('Jajpur Hardware Listing'), findsOneWidget);
      expect(find.text('Approved listing · Jajpur'), findsOneWidget);
      expect(find.text('Request review'), findsNWidgets(2));
      await tester.tap(find.text('Request review').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('claim_statement')),
        'I own and operate this local hardware shop.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Pending admin review'), findsOneWidget);
      expect(find.text('Your claim requests'), findsOneWidget);
      expect(find.text('Waiting for administrator review'), findsOneWidget);
    },
  );

  testWidgets(
    'Switching between Register New and Claim Existing modes works dynamically',
    (tester) async {
      await tester.pumpWidget(createTestWidget(initialMode: 0));
      await tester.pumpAndSettle();

      expect(find.text('Select Enterprise Classification'), findsOneWidget);

      // Tap Claim Existing in segmented control
      await tester.tap(find.text('Claim Existing'));
      await tester.pumpAndSettle();

      expect(find.text('Available listings for claim'), findsOneWidget);
      expect(
        find.text('Enter at least 2 characters to search approved listings.'),
        findsOneWidget,
      );
      expect(find.text('Maa Tarini Hardware & Sanitary'), findsNothing);

      // Tap Register New
      await tester.tap(find.text('Register New'));
      await tester.pumpAndSettle();

      expect(find.text('Select Enterprise Classification'), findsOneWidget);
    },
  );

  testWidgets(
    'Selecting business models (Enterprise Classifications) updates selection cleanly',
    (tester) async {
      await tester.pumpWidget(createTestWidget(initialMode: 0));
      await tester.pumpAndSettle();

      // Default selection is Retail Shop & Showroom
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // Tap Skilled Trade & Professional
      final proFinder = find.byKey(
        const ValueKey('enterprise_type_service_pro'),
      );
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
      final wellnessFinder = find.byKey(
        const ValueKey('enterprise_type_wellness'),
      );
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
    },
  );
}
