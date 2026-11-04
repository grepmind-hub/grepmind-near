import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dio/dio.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/home_feed_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_catalog_screen.dart';
import 'package:grepmind_mobile/core/screens/home_screen.dart';
import 'package:grepmind_mobile/core/screens/home_new_near_you_screen.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/utils/contact_actions.dart';

/// Real merchant catalog widgets + real HTTP persistence on the Android emulator.
/// Authentication uses generated local OTP accounts; device secure storage is untouched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Validate merchant catalog, offers, contact links and operating schedule',
    (tester) async {
      const encoded = String.fromEnvironment('UI_FIXTURES_GZIP');
      const mode = String.fromEnvironment('UI_MODE', defaultValue: 'cycle');
      if (encoded.isEmpty) {
        throw StateError(
          'Run scripts/merchant_ui_injection.ps1 to generate fixtures.',
        );
      }
      final manifest = jsonDecode(
        utf8.decode(GZipCodec().decode(base64Decode(encoded))),
      ) as Map<String, dynamic>;
      final cases = (manifest['Cases'] as List).cast<Map<String, dynamic>>();
      if (cases.isEmpty) {
        throw StateError('No generated cases.');
      }
      final verifiedImages = <String>{};
      apiClient.init();
      // Use this test's verified bearer token, never the device owner's saved session.
      apiClient.dio.interceptors.clear();
      final tokens = <String, String>{};
      final launchedUrls = <String>[];

      Future<void> waitFor(bool Function() predicate, String message) async {
        for (var attempt = 0; attempt < 300; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (predicate()) return;
        }
        fail(message);
      }

      Future<String> login(
        String phone, {
        String expectedRole = 'merchant',
      }) async {
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
        expect((user['roles'] as List).contains(expectedRole), isTrue);
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
              await tester.enterText(
                find.byKey(const Key('modal_product_desc')),
                entry['ProductDescription'] as String,
              );
              await tester.enterText(
                find.byKey(const Key('modal_product_image_url')),
                entry['ImageURL'] as String,
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
              final savedRows = rows
                  .where((dynamic p) => p['name'] == name)
                  .toList();
              expect(savedRows.length, 1);
              expect(
                savedRows.single['description'],
                entry['ProductDescription'],
              );
              expect(savedRows.single['image_url'], entry['ImageURL']);
              final product = container
                  .read(merchantCatalogProvider)
                  .products
                  .singleWhere((p) => p.name == name);
              await tester.tap(
                find.byKey(Key('edit_product_btn_${product.id}')),
              );
              await tester.pumpAndSettle();
              final updatedName = '$name updated';
              await tester.enterText(
                find.byKey(const Key('modal_product_name')),
                updatedName,
              );
              final saveEdit = find.byKey(const Key('save_product_btn'));
              await tester.ensureVisible(saveEdit);
              await tester.tap(saveEdit);
              await waitFor(
                () => container
                    .read(merchantCatalogProvider)
                    .products
                    .any((p) => p.id == product.id && p.name == updatedName),
                'Product edit was not persisted through the merchant UI',
              );
              final updatedVisible = await apiClient.get(
                '/businesses/$businessId/products',
              );
              expect(
                (updatedVisible.data['data'] as List).any(
                  (dynamic p) =>
                      p['id'] == product.id && p['name'] == updatedName,
                ),
                isTrue,
              );
              await container
                  .read(merchantCatalogProvider.notifier)
                  .updateProduct(product.id, {'name': name});
              await waitFor(
                () => container
                    .read(merchantCatalogProvider)
                    .products
                    .any((p) => p.id == product.id && p.name == name),
                'Product could not be restored after edit validation',
              );
              final newArrivals = await apiClient.get(
                '/catalog/new-arrivals',
                queryParameters: {
                  'city': entry['City'],
                  'type': 'products',
                  'limit': 50,
                },
              );
              expect(
                (newArrivals.data['data'] as List).any(
                  (dynamic p) => p['id'] == product.id,
                ),
                isTrue,
              );
              final imageUrl = entry['ImageURL'] as String;
              if (verifiedImages.add(imageUrl)) {
                final imageResponse = await apiClient.dio.get<List<int>>(
                  imageUrl,
                  options: Options(responseType: ResponseType.bytes),
                );
                expect(imageResponse.statusCode, 200);
                expect(imageResponse.data, isNotEmpty);
              }

              final now = DateTime.now().toUtc();
              final offerResponse = await apiClient.post(
                '/merchant/businesses/$businessId/offers',
                data: {
                  'title': entry['OfferTitle'],
                  'description':
                      'Test fixture offer for merchant flow validation.',
                  'starts_at': now
                      .add(const Duration(minutes: 1))
                      .toIso8601String(),
                  'ends_at': now.add(const Duration(days: 7)).toIso8601String(),
                  'terms': 'Local validation fixture; no customer payment collected.',
                  'discount_percent': 10,
                },
              );
              final offer = offerResponse.data['data'] as Map<String, dynamic>;
              expect(offer['status'], 'pending');
              final offerId = offer['id'] as String;
              await apiClient.patch(
                '/merchant/offers/$offerId',
                data: {'title': '${entry['OfferTitle']} updated'},
              );
              var merchantOffers = await apiClient.get(
                '/merchant/businesses/$businessId/offers',
              );
              var offers = (merchantOffers.data['data'] as List)
                  .cast<Map<String, dynamic>>();
              expect(
                offers.any(
                  (o) =>
                      o['id'] == offerId &&
                      o['title'].toString().endsWith('updated'),
                ),
                isTrue,
              );

              if (cases.length > 1) {
                final other = cases.firstWhere(
                  (candidate) => candidate['BusinessID'] != businessId,
                );
                final otherToken = await login(other['Phone'] as String);
                apiClient.dio.options.headers['Authorization'] =
                    'Bearer $otherToken';
                try {
                  await apiClient.get(
                    '/merchant/businesses/$businessId/offers',
                  );
                  fail('A different merchant read another business\'s offers');
                } on DioException catch (error) {
                  expect(error.response?.statusCode, 403);
                }
                try {
                  await apiClient.delete('/merchant/offers/$offerId');
                  fail(
                    'A different merchant deleted another business\'s offer',
                  );
                } on DioException catch (error) {
                  expect(error.response?.statusCode, 403);
                }
                apiClient.dio.options.headers['Authorization'] =
                    'Bearer $token';
              }

              final hoursResponse = await apiClient.get(
                '/merchant/operating-hours',
              );
              final hours = (hoursResponse.data['data'] as List?) ?? [];
              expect(hours.length, 7);
              expect(
                hours.where((dynamic h) => h['is_closed'] == false).length,
                6,
              );
              final profileResponse = await apiClient.get(
                '/businesses/$businessId',
              );
              final profile =
                  profileResponse.data['data'] as Map<String, dynamic>;
              expect(profile['address_text'], entry['Address']);
              expect(profile['phone_e164'], entry['Phone']);
              expect(profile['whatsapp_e164'], entry['Phone']);
              expect((profile['business_hours'] as List).length, 7);

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

              // The common customer profile/contact/schedule UI is exercised
              // once per city; each one of the 38 categories still receives a
              // real merchant catalog UI create and API discovery assertion.
              final firstCaseInCity =
                  cases.indexWhere(
                    (candidate) => candidate['City'] == entry['City'],
                  ) ==
                  cases.indexOf(entry);
              if (firstCaseInCity) {
                final customerToken = await login(
                  manifest['CustomerPhone'] as String,
                  expectedRole: 'customer',
                );
                apiClient.dio.options.headers['Authorization'] =
                    'Bearer $customerToken';
                final customerContainer = ProviderContainer(
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
                    contactActionsProvider.overrideWith(
                      (ref) => ContactActions(
                        launcher: (uri) async {
                          launchedUrls.add(uri.toString());
                          return true;
                        },
                      ),
                    ),
                  ],
                );
                await tester.pumpWidget(
                  UncontrolledProviderScope(
                    container: customerContainer,
                    child: const MaterialApp(home: HomeScreen()),
                  ),
                );
                await waitFor(
                  () =>
                      customerContainer
                          .read(homeFeedProvider(entry['City'] as String))
                          .valueOrNull
                          ?.newArrivals
                          .any((item) => item.name == name) ==
                      true,
                  'Customer Home feed did not receive the newly published merchant product',
                );
                await tester.scrollUntilVisible(
                  find.text(name),
                  180,
                  scrollable: find.byType(Scrollable).first,
                );
                expect(find.text(name), findsOneWidget);
                await tester.scrollUntilVisible(
                  find.text('See all'),
                  180,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.tap(find.text('See all').first);
                await tester.pumpAndSettle();
                expect(find.byType(HomeNewNearYouScreen), findsOneWidget);
                await waitFor(
                  () => find.text(name).evaluate().isNotEmpty,
                  'See all catalog arrivals did not show the newly published product',
                );
                await tester.tap(find.text('Products'));
                await tester.pumpAndSettle();
                expect(find.text(name), findsOneWidget);
                await tester.tap(find.text('Services'));
                await tester.pumpAndSettle();
                expect(find.text(name), findsNothing);
                await tester.tap(find.text('All'));
                await tester.pumpAndSettle();
                expect(find.text(name), findsOneWidget);
                await tester.pageBack();
                await tester.pumpAndSettle();
                await tester.pumpWidget(
                  UncontrolledProviderScope(
                    container: customerContainer,
                    child: MaterialApp(
                      home: BusinessDetailScreen(businessId: businessId),
                    ),
                  ),
                );
                await waitFor(
                  () =>
                      customerContainer.read(businessDetailProvider).detail !=
                          null &&
                      !customerContainer.read(businessDetailProvider).isLoading,
                  'Customer business profile did not load',
                );
                expect(
                  find.text(
                    'No active offers are available from this business.',
                  ),
                  findsNothing,
                );
                final callLabel = find.text('Call');
                expect(callLabel, findsOneWidget);
                final callCount = launchedUrls.length;
                await tester.tap(callLabel);
                await waitFor(
                  () => launchedUrls.length > callCount,
                  'Call action did not launch a dialer URI',
                );
                expect(launchedUrls.last, 'tel:${entry['Phone']}');
                final whatsappLabel = find.text('WhatsApp');
                final whatsappCount = launchedUrls.length;
                await tester.tap(whatsappLabel);
                await waitFor(
                  () => launchedUrls.length > whatsappCount,
                  'WhatsApp action did not launch a chat URI',
                );
                expect(
                  launchedUrls.last,
                  'https://wa.me/${(entry['Phone'] as String).replaceAll('+', '')}',
                );
                final scheduleHeading = find.text('Operating Schedule');
                for (
                  var attempt = 0;
                  attempt < 8 && scheduleHeading.evaluate().isEmpty;
                  attempt++
                ) {
                  await tester.drag(
                    find.byType(Scrollable).last,
                    const Offset(0, -420),
                  );
                  await tester.pumpAndSettle();
                }
                expect(scheduleHeading, findsOneWidget);
                await tester.ensureVisible(find.text('Operating Schedule'));
                await tester.pumpAndSettle();
                expect(find.textContaining('9:00 AM'), findsWidgets);
                await tester.tap(find.text('Offers').first);
                await tester.pumpAndSettle();
                expect(
                  find.text(
                    'No active offers are available from this business.',
                  ),
                  findsOneWidget,
                );
                await tester.pumpWidget(const SizedBox.shrink());
                customerContainer.dispose();
                apiClient.dio.options.headers['Authorization'] =
                    'Bearer $token';
                merchantOffers = await apiClient.get(
                  '/merchant/businesses/$businessId/offers',
                );
                offers = (merchantOffers.data['data'] as List)
                    .cast<Map<String, dynamic>>();
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
                    tester.view.physicalSize.width /
                    tester.view.devicePixelRatio;
                for (
                  var attempt = 0;
                  attempt < 30 &&
                      (categoryChip.evaluate().isEmpty ||
                          tester.getRect(categoryChip).left < 4 ||
                          tester.getRect(categoryChip).right >
                              logicalWidth - 4);
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
              }
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
              final merchantOffers = await apiClient.get(
                '/merchant/businesses/$businessId/offers',
              );
              final offers = (merchantOffers.data['data'] as List)
                  .cast<Map<String, dynamic>>();
              for (final offer in offers.where(
                (o) => (o['title'] as String).contains('QA Fixture'),
              )) {
                await apiClient.delete('/merchant/offers/${offer['id']}');
              }
              final afterOfferDelete = await apiClient.get(
                '/merchant/businesses/$businessId/offers',
              );
              expect(
                (afterOfferDelete.data['data'] as List).where(
                  (dynamic o) => (o['title'] as String).contains('QA Fixture'),
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
