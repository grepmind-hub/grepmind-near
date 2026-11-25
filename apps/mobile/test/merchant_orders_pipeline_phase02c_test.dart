import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_platform_orders_screen.dart';

void main() {
  setUpAll(() {
    apiClient.init(baseUrl: 'https://orders-phase02c.test/api/v1');
  });

  setUp(() => apiClient.dio.interceptors.clear());

  testWidgets(
    'Phase 02C: pipeline tabs filter orders and display badge counts',
    (tester) async {
      final ordersList = [
        {
          'id': 'order-new-1',
          'reference_code': 'AB-NEW-101',
          'status': 'placed',
          'vertical': 'food',
          'delivery_locality': 'Kuanpal',
          'delivery_district': 'Cuttack',
          'items': [
            {
              'product_name': 'Chicken Biryani',
              'quantity': 2,
              'unit_label': 'full',
            },
          ],
          'payment_method': 'cash_on_delivery',
          'cod_collection_state': 'due',
        },
        {
          'id': 'order-prep-1',
          'reference_code': 'AB-PREP-102',
          'status': 'preparing',
          'vertical': 'food',
          'delivery_locality': 'Salipur',
          'delivery_district': 'Cuttack',
          'items': [
            {
              'product_name': 'Paneer Butter Masala',
              'quantity': 1,
              'unit_label': 'plate',
            },
          ],
          'payment_method': 'upi',
          'payment_status': 'paid',
        },
        {
          'id': 'order-ready-1',
          'reference_code': 'AB-READY-103',
          'status': 'ready_for_pickup',
          'vertical': 'grocery',
          'delivery_locality': 'Choudwar',
          'delivery_district': 'Cuttack',
          'items': [
            {
              'product_name': 'Mustard Oil 1L',
              'quantity': 3,
              'unit_label': 'bottle',
            },
          ],
          'payment_method': 'upi',
          'payment_status': 'paid',
        },
        {
          'id': 'order-done-1',
          'reference_code': 'AB-DONE-104',
          'status': 'delivered',
          'vertical': 'food',
          'delivery_locality': 'Kuanpal',
          'delivery_district': 'Cuttack',
          'items': [
            {
              'product_name': 'Chhena Poda 500g',
              'quantity': 1,
              'unit_label': 'box',
            },
          ],
          'payment_method': 'upi',
          'payment_status': 'paid',
        },
      ];

      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/platform-orders')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'data': ordersList},
                ),
              );
            }
            if (options.path.endsWith('/delivery-dispatch')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'data': []},
                ),
              );
            }
            return handler.reject(
              DioException(requestOptions: options, message: 'Unexpected'),
            );
          },
        ),
      );

      final profile = _FakeMerchantProfile();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            merchantProfileProvider('').overrideWith((ref) => profile),
          ],
          child: const MaterialApp(home: MerchantPlatformOrdersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Orders & Fulfillment'), findsOneWidget);
      expect(find.text('Partner Orders Pipeline · Abashyaka'), findsOneWidget);

      // Verify TabBar with badge counts
      expect(find.widgetWithText(Tab, 'All'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'New Orders'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Preparing'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Ready for Pickup'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'History'), findsOneWidget);

      // In "All" tab, all 4 orders are listed
      expect(find.textContaining('AB-NEW-101'), findsOneWidget);
      expect(find.textContaining('AB-PREP-102'), findsOneWidget);
      expect(find.textContaining('AB-READY-103'), findsOneWidget);
      expect(find.textContaining('AB-DONE-104'), findsOneWidget);

      // Switch to "New Orders" tab
      await tester.tap(find.widgetWithText(Tab, 'New Orders'));
      await tester.pumpAndSettle();

      expect(find.textContaining('AB-NEW-101'), findsOneWidget);
      expect(find.textContaining('AB-PREP-102'), findsNothing);
      expect(find.textContaining('AB-READY-103'), findsNothing);

      // Switch to "Preparing" tab
      await tester.tap(find.widgetWithText(Tab, 'Preparing'));
      await tester.pumpAndSettle();

      expect(find.textContaining('AB-PREP-102'), findsOneWidget);
      expect(find.textContaining('AB-NEW-101'), findsNothing);

      // Switch to "Ready for Pickup" tab
      await tester.tap(find.widgetWithText(Tab, 'Ready for Pickup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('AB-READY-103'), findsOneWidget);
      expect(find.textContaining('AB-PREP-102'), findsNothing);

      // Switch to "History" tab
      await tester.tap(find.widgetWithText(Tab, 'History'));
      await tester.pumpAndSettle();

      expect(find.textContaining('AB-DONE-104'), findsOneWidget);
      expect(find.textContaining('AB-READY-103'), findsNothing);
    },
  );

  testWidgets(
    'Phase 02C: Kitchen Ticket modal displays itemized breakdown and notes',
    (tester) async {
      final orderWithInstructions = {
        'id': 'order-ticket-1',
        'reference_code': 'AB-TICKET-200',
        'status': 'placed',
        'vertical': 'food',
        'delivery_locality': 'Infocity',
        'delivery_district': 'Bhubaneswar',
        'special_instructions': 'Extra spicy, less oil please.',
        'items': [
          {
            'product_name': 'Dalma Rice Combo',
            'quantity': 2,
            'unit_label': 'thali',
          },
          {
            'product_name': 'Rasagola 2 pcs',
            'quantity': 1,
            'unit_label': 'pack',
          },
        ],
        'payment_method': 'cash_on_delivery',
        'cod_collection_state': 'due',
      };

      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/platform-orders')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [orderWithInstructions],
                  },
                ),
              );
            }
            if (options.path.endsWith('/delivery-dispatch')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'data': []},
                ),
              );
            }
            return handler.reject(
              DioException(requestOptions: options, message: 'Unexpected'),
            );
          },
        ),
      );

      final profile = _FakeMerchantProfile();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            merchantProfileProvider('').overrideWith((ref) => profile),
          ],
          child: const MaterialApp(home: MerchantPlatformOrdersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Expand the order card
      await tester.tap(find.textContaining('AB-TICKET-200'));
      await tester.pumpAndSettle();

      // Verify Kitchen Ticket button
      final ticketButton = find.widgetWithText(TextButton, 'Kitchen Ticket');
      expect(ticketButton, findsOneWidget);
      await tester.tap(ticketButton);
      await tester.pumpAndSettle();

      // Verify Kitchen Ticket sheet
      expect(find.text('KITCHEN TICKET'), findsOneWidget);
      expect(find.text('ORDER ITEMS'), findsOneWidget);
      expect(find.text('Dalma Rice Combo'), findsNWidgets(2));
      expect(find.text('Rasagola 2 pcs'), findsNWidgets(2));
      expect(find.text('SPECIAL NOTES'), findsOneWidget);
      expect(find.text('Extra spicy, less oil please.'), findsOneWidget);

      // Close Kitchen Ticket
      await tester.tap(find.text('Back to Orders'));
      await tester.pumpAndSettle();
      expect(find.text('KITCHEN TICKET'), findsNothing);
    },
  );
}

class _FakeMerchantProfile extends MerchantProfileNotifier {
  _FakeMerchantProfile() : super('') {
    state = state.copyWith(profile: _business);
  }

  @override
  Future<void> load() async {
    state = state.copyWith(profile: _business, isLoading: false);
  }
}

const _business = {
  'id': 'qa-business-1',
  'name': 'Cuttack Chandi Paints & Hardware',
  'status': 'approved',
};
