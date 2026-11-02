import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_catalog_screen.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';

/// Real merchant catalog widgets + real HTTP persistence on the Android emulator.
/// Authentication uses generated local OTP accounts; device secure storage is untouched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Inject and remove products for every live city/category through UI',
    (tester) async {
      const encoded = String.fromEnvironment('UI_FIXTURES');
      const mode = String.fromEnvironment('UI_MODE', defaultValue: 'cycle');
      if (encoded.isEmpty)
        throw StateError(
          'Run scripts/merchant_ui_injection.ps1 to generate fixtures.',
        );
      final manifest = jsonDecode(
        utf8.decode(base64Decode(encoded)),
      ) as Map<String, dynamic>;
      final cases = (manifest['Cases'] as List).cast<Map<String, dynamic>>();
      if (cases.isEmpty) throw StateError('No generated cases.');
      apiClient.init();
      // Use this test's verified bearer token, never the device owner's saved session.
      apiClient.dio.interceptors.clear();
      final tokens = <String, String>{};

      Future<void> waitFor(bool Function() predicate, String message) async {
        for (var attempt = 0; attempt < 300; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (predicate()) return;
        }
        fail(message);
      }

      Future<String> login(String phone) async {
        if (tokens.containsKey(phone)) return tokens[phone]!;
        apiClient.dio.options.headers.remove('Authorization');
        final otp = await apiClient.post(
          '/auth/otp/request',
          data: {'phone_e164': phone},
        );
        final code = otp.data['data']['otp_code'] as String?;
        if (code == null) throw StateError('Local OTP provider required.');
        final session = await apiClient.post(
          '/auth/otp/verify',
          data: {'phone_e164': phone, 'otp_code': code},
        );
        final user = session.data['data']['user'] as Map<String, dynamic>;
        expect((user['roles'] as List).contains('merchant'), isTrue);
        final token = session.data['data']['access_token'] as String;
        tokens[phone] = token;
        return token;
      }

      final phases = mode == 'cycle' ? ['inject', 'delete'] : [mode];
      for (final phase in phases) {
        for (final entry in cases) {
          final token = await login(entry['Phone'] as String);
          apiClient.dio.options.headers['Authorization'] = 'Bearer $token';
          final name = entry['ProductName'] as String;
          final businessId = entry['BusinessID'] as String;
          final container = ProviderContainer(
            overrides: [
              appLocationProvider.overrideWith((ref) {
                final location = LocationNotifier();
                location.setLocation(
                  AppLocation(
                    cityName: entry['City'] as String,
                    latitude: (entry['Latitude'] as num).toDouble(),
                    longitude: (entry['Longitude'] as num).toDouble(),
                  ),
                );
                return location;
              }),
            ],
          );
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                key: UniqueKey(),
                home: const MerchantCatalogScreen(),
              ),
            ),
          );
          try {
            await waitFor(
              () => !container.read(merchantCatalogProvider).isLoading,
              'Merchant catalog did not finish loading',
            );
            expect(container.read(merchantCatalogProvider).error, isNull);
            if (phase == 'inject') {
              await tester.tap(find.byKey(const Key('add_product_fab')));
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byKey(const Key('modal_product_name')),
                name,
              );
              await tester.enterText(
                find.byKey(const Key('modal_product_price')),
                '${entry['Price']}',
              );
              FocusManager.instance.primaryFocus?.unfocus();
              final save = find.byKey(const Key('save_product_btn'));
              await tester.ensureVisible(save);
              await tester.tap(save);
              await waitFor(
                () =>
                    find.text(name).evaluate().isNotEmpty &&
                    find
                        .byKey(const Key('modal_product_name'))
                        .evaluate()
                        .isEmpty,
                'Product was not saved through UI',
              );
              final visible = await apiClient.get(
                '/businesses/$businessId/products',
              );
              final rows = (visible.data['data'] as List?) ?? [];
              expect(rows.where((dynamic p) => p['name'] == name).length, 1);
              final nearby = await apiClient.get(
                '/nearby',
                queryParameters: {
                  'lat': entry['Latitude'],
                  'lng': entry['Longitude'],
                  'city': entry['City'],
                  'category_slug': entry['CategorySlug'],
                  'limit': 50,
                },
              );
              final shops = (nearby.data['data'] as List?) ?? [];
              expect(shops.any((dynamic b) => b['id'] == businessId), isTrue);
              expect(
                shops.every(
                  (dynamic b) =>
                      b['city'] == entry['City'] &&
                      b['category_slug'] == entry['CategorySlug'],
                ),
                isTrue,
              );
              // Exercise actual map/radar filtering without requesting device permissions
              // or claiming the generated city center is the emulator's physical GPS.
              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: container,
                  child: MaterialApp(
                    key: UniqueKey(),
                    home: const NearbyMapScreen(
                      useDeviceLocation: false,
                      initialRadarView: true,
                    ),
                  ),
                ),
              );
              await waitFor(
                () =>
                    container.read(categoriesProvider).items.isNotEmpty &&
                    !container.read(mapBusinessesProvider).isLoading,
                'Map taxonomy/listings did not load',
              );
              await tester.pump(const Duration(milliseconds: 100));
              final categoryChip = find.byKey(
                ValueKey('map_category_${entry['CategorySlug']}'),
              );
              final categoryList = find.byType(Scrollable).first;
              final logicalWidth =
                  tester.view.physicalSize.width / tester.view.devicePixelRatio;
              for (
                var attempt = 0;
                attempt < 30 &&
                    (categoryChip.evaluate().isEmpty ||
                        tester.getRect(categoryChip).left < 4 ||
                        tester.getRect(categoryChip).right > logicalWidth - 4);
                attempt++
              ) {
                await tester.drag(categoryList, const Offset(-160, 0));
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(categoryChip, findsOneWidget);
              final chipRect = tester.getRect(categoryChip);
              expect(chipRect.left, greaterThanOrEqualTo(4));
              expect(chipRect.right, lessThanOrEqualTo(logicalWidth - 4));
              await tester.tapAt(chipRect.center);
              await waitFor(
                () =>
                    !container.read(mapBusinessesProvider).isLoading &&
                    container
                        .read(mapBusinessesProvider)
                        .items
                        .any((b) => b.id == businessId),
                'Map did not show the injected category listing',
              );
              expect(
                container
                    .read(mapBusinessesProvider)
                    .items
                    .every(
                      (b) =>
                          b.city == entry['City'] &&
                          b.categorySlug == entry['CategorySlug'],
                    ),
                isTrue,
              );
              expect(
                find.byKey(ValueKey('radar_business_$businessId')),
                findsOneWidget,
              );
            } else if (phase == 'delete') {
              final product = container
                  .read(merchantCatalogProvider)
                  .products
                  .singleWhere((p) => p.name == name);
              final remove = find.byKey(
                Key('delete_product_btn_${product.id}'),
              );
              await tester.ensureVisible(remove);
              await tester.tap(remove);
              await tester.pumpAndSettle();
              await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
              await waitFor(
                () =>
                    !container.read(merchantCatalogProvider).isLoading &&
                    container
                        .read(merchantCatalogProvider)
                        .products
                        .every((p) => p.id != product.id),
                'UI deletion was not persisted',
              );
              final visible = await apiClient.get(
                '/businesses/$businessId/products',
              );
              expect(
                ((visible.data['data'] as List?) ?? []).where(
                  (dynamic p) => p['id'] == product.id,
                ),
                isEmpty,
              );
            } else {
              throw StateError('Unknown UI mode');
            }
            debugPrint(
              'PASS UI $phase ${entry['City']} / ${entry['CategorySlug']}',
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            container.dispose();
          }
        }
      }
      tokens.clear();
      apiClient.dio.options.headers.remove('Authorization');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
