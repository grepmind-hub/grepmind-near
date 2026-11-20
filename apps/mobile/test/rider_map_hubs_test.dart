import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/rider_locality_hubs_screen.dart';
import 'package:grepmind_mobile/core/screens/rider_map_screen.dart';

void main() {
  setUpAll(() => apiClient.init(baseUrl: 'https://rider.test/api/v1'));
  setUp(() => apiClient.dio.interceptors.clear());

  testWidgets(
    'RiderDeliveryRouteMapScreen shows turn-by-turn instruction and destination actions',
    (tester) async {
      final assignment = {
        'order_reference': 'GN-TEST03C',
        'execution_state': 'en_route',
        'pickup_business_name': 'Grand Kitchen',
        'recipient_name': 'Santosh Behera',
        'destination_locality': 'Kuanpal',
        'destination_district': 'Cuttack',
        'destination_address': 'Plot 42, Market Complex, Kuanpal',
        'contact_phone': '+919990000171',
      };

      var handoverConfirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: RiderDeliveryRouteMapScreen(
            assignment: assignment,
            onConfirmHandover: () {
              handoverConfirmed = true;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check header and order ref
      expect(find.text('Delivery Route Navigation'), findsOneWidget);
      expect(find.text('Order: GN-TEST03C'), findsOneWidget);
      expect(find.text('Route Preview'), findsOneWidget);

      // Check turn-by-turn instruction (Screen 18)
      expect(
        find.text('In 250m, continue onto Cuttack-Kuanpal Road'),
        findsOneWidget,
      );
      expect(
        find.text('Destination: Kuanpal · 2.4 km (~12 mins)'),
        findsOneWidget,
      );

      // Check destination floating sheet (Screen 14)
      expect(find.text('EN ROUTE TO DROP-OFF'), findsOneWidget);
      expect(find.text('Santosh Behera'), findsOneWidget);
      expect(find.text('Plot 42, Market Complex, Kuanpal'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Confirm customer handover'), findsOneWidget);

      // Tap confirm customer handover action
      await tester.tap(find.text('Confirm customer handover'));
      await tester.pump();
      expect(handoverConfirmed, isTrue);
    },
  );

  testWidgets(
    'RiderLocalityHubsScreen renders distribution radar, shift radius slider and localities',
    (tester) async {
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = switch (options.path) {
              '/rider/localities' => {
                'data': [
                  {
                    'id': 'loc-1',
                    'name': 'Kuanpal',
                    'district_name': 'Cuttack',
                    'delivery_enabled': true,
                  },
                  {
                    'id': 'loc-2',
                    'name': 'Chhatia',
                    'district_name': 'Jajpur',
                    'delivery_enabled': true,
                  },
                  {
                    'id': 'loc-3',
                    'name': 'Jagatpur',
                    'district_name': 'Cuttack',
                    'delivery_enabled': false,
                  },
                ],
              },
              '/rider/profile' => {
                'data': {
                  'id': 'rider-123',
                  'display_name': 'QA Rider',
                  'approved_localities': [
                    {'id': 'loc-1', 'name': 'Kuanpal', 'district': 'Cuttack'},
                  ],
                },
              },
              _ => {'data': <dynamic>[]},
            };
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: data),
            );
          },
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(home: RiderLocalityHubsScreen()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check header and primary hub card (Screen 19)
      expect(find.text('Service Locality Hubs'), findsOneWidget);
      expect(find.text('Cuttack & Jajpur Central Hubs'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('1 Active'), findsOneWidget);

      // Check shift delivery radius slider and presets (Screen 20)
      expect(find.text('Shift Delivery Radius'), findsOneWidget);
      expect(find.text('5.0 km'), findsOneWidget);
      expect(find.text('8 km'), findsOneWidget);
      expect(find.text('10 km'), findsOneWidget);

      // Check operational locality directory
      expect(find.text('Operational Locality Directory'), findsOneWidget);
      expect(find.text('Kuanpal'), findsWidgets);
      expect(find.text('YOUR HUB'), findsOneWidget);
      expect(find.text('Chhatia'), findsWidgets);
      expect(find.text('Jagatpur'), findsWidgets);

      // Tap preset 10 km
      await tester.ensureVisible(find.text('10 km'));
      await tester.tap(find.text('10 km'));
      await tester.pump();
      expect(find.text('10.0 km'), findsWidgets);

      // Tap Apply Shift Radius
      expect(find.text('Apply Shift Radius'), findsOneWidget);
      await tester.ensureVisible(find.text('Apply Shift Radius'));
      await tester.tap(find.text('Apply Shift Radius'));
      await tester.pump(const Duration(milliseconds: 700));
    },
  );
}
