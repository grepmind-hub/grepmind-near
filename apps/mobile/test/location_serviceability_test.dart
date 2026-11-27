import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/features/location/location_selection_sheet.dart';
import 'package:grepmind_mobile/features/location/serviceability_service.dart';

void main() {
  const supported = {
    'serviceable': true,
    'status': 'active',
    'district_name': 'Cuttack',
    'locality_name': 'Kuanpal',
    'locality_id': 'kuanpal-test',
    'capabilities': {'grocery_delivery': false},
  };
  const outside = {'serviceable': false, 'status': 'outside_service_area'};
  Map<String, Object?>? decision;
  bool listUnavailable = false;
  final checkedPins = <String>[];

  setUpAll(() => apiClient.init(baseUrl: 'https://coverage.test/api/v1'));
  setUp(() {
    decision = null;
    listUnavailable = false;
    checkedPins.clear();
    apiClient.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            Object? data;
            if (request.path == '/serviceability/locations') {
              data = listUnavailable ? null : <Object>[];
            } else if (request.path == '/serviceability/check') {
              checkedPins.add((request.data as Map)['pin_code'] as String);
              data = decision;
            }
            if (data == null) {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.connectionError,
                ),
              );
            } else {
              handler.resolve(
                Response(requestOptions: request, data: {'data': data}),
              );
            }
          },
        ),
      );
  });

  Future<ProviderContainer> openSheet(WidgetTester tester) async {
    final scope = ProviderContainer();
    addTearDown(scope.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () => LocationSelectionSheet.show(context),
                  child: const Text('Open locations'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open locations'));
    await tester.pumpAndSettle();
    return scope;
  }

  testWidgets('pilot PIN outage keeps browsing location and retries same PIN', (
    tester,
  ) async {
    final scope = await openSheet(tester);
    final original = scope.read(appLocationProvider);
    await tester.enterText(find.byType(TextField), '754204');
    await tester.pumpAndSettle();

    expect(find.text('We couldn’t check coverage right now'), findsOneWidget);
    expect(find.text('Notify me when available'), findsNothing);
    expect(scope.read(appLocationProvider), same(original));

    decision = supported;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(checkedPins, ['754204', '754204']);
    expect(scope.read(appLocationProvider).localityId, 'kuanpal-test');
  });

  testWidgets(
    'confirmed unsupported PIN shows the existing notification option',
    (tester) async {
      decision = outside;
      await openSheet(tester);
      await tester.enterText(find.byType(TextField), '110001');
      await tester.pumpAndSettle();

      expect(find.text("We're not in your area just yet."), findsOneWidget);
      expect(find.text('Notify me when available'), findsOneWidget);
      expect(find.text('We couldn’t check coverage right now'), findsNothing);
    },
  );

  testWidgets('location directory failure does not show hardcoded hubs', (
    tester,
  ) async {
    listUnavailable = true;
    await openSheet(tester);
    expect(find.text('We couldn’t check coverage right now'), findsOneWidget);
    expect(find.text('Delivery Active'), findsNothing);

    listUnavailable = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No locations available'), findsOneWidget);
  });

  test('an absent decision is unavailable and an Admin capability survives parsing', () async {
    final service = ServiceabilityService();
    decision = {};
    expect(
      (await service.checkServiceability(pinCode: '754204')).isUnavailable,
      isTrue,
    );

    decision = supported;
    final active = await service.checkServiceability(pinCode: '754204');
    expect(active.serviceable, isTrue);
    expect(active.capabilities.groceryDelivery, isFalse);
  });
}
