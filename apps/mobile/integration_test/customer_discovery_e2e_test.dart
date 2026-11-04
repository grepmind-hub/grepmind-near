import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/explore_screen.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';
import 'package:grepmind_mobile/core/screens/onboarding_screen.dart';
import 'package:grepmind_mobile/core/screens/service_pro_screen.dart';
import 'package:grepmind_mobile/core/widgets/business_card.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grepmind_mobile/main.dart';

/// Runs the customer OTP and discovery flow against disposable local fixtures.
/// The test gets its fresh phone and listings from merchant_ui_injection.ps1.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fresh OTP customer discovers Cuttack and Jajpur listings', (
    tester,
  ) async {
    const encoded = String.fromEnvironment('UI_FIXTURES_GZIP');
    if (encoded.isEmpty) {
      throw StateError(
        'Run scripts/merchant_ui_injection.ps1 -Action Run -Scenario Discovery.',
      );
    }
    final manifest = jsonDecode(
      utf8.decode(GZipCodec().decode(base64Decode(encoded))),
    ) as Map<String, dynamic>;
    final cases = (manifest['Cases'] as List).cast<Map<String, dynamic>>();
    final customerPhone = manifest['CustomerPhone'] as String?;
    if (cases.isEmpty || customerPhone == null || customerPhone.isEmpty) {
      throw StateError('Discovery QA fixtures are incomplete.');
    }

    apiClient.init();
    apiClient.dio.interceptors.clear();
    apiClient.dio.options.headers.remove('Authorization');
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith((ref) => _DiscoveryAuthNotifier())],
    );

    Future<void> waitFor(bool Function() predicate, String failure) async {
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (predicate()) return;
      }
      fail(failure);
    }

    Future<void> openTab(String label, Type screenType) async {
      final tab = find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text(label),
      );
      await tester.tap(tab);
      await waitFor(
        () => find.byType(screenType).evaluate().isNotEmpty,
        '$label screen did not open.',
      );
    }

    Future<void> selectCity(String city) async {
      if (container.read(appLocationProvider).cityName == city) return;
      final selector = find.byKey(const Key('explore_location_selector'));
      final scrollView = find.byKey(const Key('explore_screen_scroll_view'));
      for (var i = 0; i < 6; i++) {
        final rect = tester.getRect(selector);
        if (rect.top >= 0 && rect.bottom <= tester.getSize(scrollView).height) {
          break;
        }
        await tester.drag(scrollView, const Offset(0, 500));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      await tester.tap(selector);
      await waitFor(
        () => find.text('Select Location').evaluate().isNotEmpty,
        'Location picker did not load for $city.',
      );
      final tile = find.ancestor(
        of: find.text(city),
        matching: find.byType(ListTile),
      );
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await waitFor(
        () => container.read(appLocationProvider).cityName == city,
        'Location picker did not select $city.',
      );
    }

    try {
      // Complete the same phone and OTP UI used by a customer. The test-only
      // notifier keeps the new session in memory and leaves device credentials
      // untouched while calling the real local OTP request/verify endpoints.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      await waitFor(
        () => find.byKey(const Key('phoneInput')).evaluate().isNotEmpty,
        'Customer login screen did not load.',
      );
      await tester.enterText(
        find.byKey(const Key('phoneInput')),
        customerPhone.substring(3),
      );
      await tester.tap(find.byKey(const Key('sendOTPButton')));
      await waitFor(
        () => find
            .textContaining('Local development code:')
            .evaluate()
            .isNotEmpty,
        'Local OTP code was not returned. The runner does not send real SMS.',
      );
      final otpLabel = tester.widget<Text>(
        find.textContaining('Local development code:').first,
      );
      final otp = otpLabel.data!.split(': ').last;
      await tester.tap(find.byKey(const Key('otpInput')));
      await tester.enterText(find.byKey(const Key('otpInput')), otp);
      await tester.tap(find.byKey(const Key('verifyOTPButton')));
      await waitFor(
        () => container.read(authProvider).isAuthenticated,
        'Fresh customer OTP verification failed.',
      );
      expect(container.read(authProvider).user!.roles, contains('customer'));
      apiClient.dio.options.headers['Authorization'] =
          'Bearer ${container.read(authProvider).accessToken}';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const GrepmindNearApp(),
        ),
      );
      await waitFor(
        () => find.byType(BottomNavigationBar).evaluate().isNotEmpty,
        'Customer application shell did not open after OTP login.',
      );

      for (final city in const ['Cuttack', 'Jajpur']) {
        await openTab('Explore', ExploreScreen);
        await selectCity(city);

        final cityCases = cases
            .where((entry) => entry['City'] == city)
            .toList(growable: false);
        expect(
          cityCases.length,
          19,
          reason: '$city should cover 19 categories.',
        );

        final exploreCase = cityCases.first;
        final categoryFilter = find.byKey(
          Key('explore_category_${exploreCase['CategorySlug']}'),
        );
        await tester.ensureVisible(categoryFilter);
        await tester.tap(categoryFilter);
        await waitFor(
          () =>
              !container.read(businessesProvider).isLoading &&
              container
                  .read(businessesProvider)
                  .items
                  .any((business) => business.id == exploreCase['BusinessID']),
          'Explore did not show the ${exploreCase['CategoryName']} listing in $city.',
        );
        final exploreItems = container.read(businessesProvider).items;
        expect(
          exploreItems.every(
            (business) => business.categorySlug == exploreCase['CategorySlug'],
          ),
          isTrue,
          reason: 'Explore category filter returned mixed categories in $city.',
        );

        final imageResponse = await apiClient.dio.get<List<int>>(
          exploreCase['ImageURL'] as String,
          options: Options(responseType: ResponseType.bytes),
        );
        expect(imageResponse.statusCode, 200);
        expect(
          imageResponse.headers.value(Headers.contentTypeHeader),
          startsWith('image/'),
          reason: 'The $city listing image did not return image content.',
        );

        final businessCard = find.ancestor(
          of: find.text(exploreCase['BusinessName'] as String).first,
          matching: find.byType(BusinessCard),
        );
        await tester.ensureVisible(businessCard);
        expect(
          find.descendant(of: businessCard, matching: find.byType(Image)),
          findsOneWidget,
        );
        await tester.tap(businessCard);
        await waitFor(
          () =>
              find.byType(BusinessDetailScreen).evaluate().isNotEmpty ||
              find.byType(ServiceProScreen).evaluate().isNotEmpty,
          'The $city Explore listing did not open its business/service profile.',
        );
        expect(find.text(exploreCase['BusinessName'] as String), findsWidgets);
        await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
        await waitFor(
          () =>
              find.byType(BusinessDetailScreen).evaluate().isEmpty &&
              find.byType(ServiceProScreen).evaluate().isEmpty,
          'Could not return to Explore after opening the $city profile.',
        );

        await openTab('Nearby', NearbyMapScreen);
        await waitFor(
          () =>
              !container.read(mapBusinessesProvider).isLoading &&
              container
                  .read(mapBusinessesProvider)
                  .items
                  .any((business) => business.city == city),
          'Nearby did not load public listings for $city.',
        );

        for (final entry in cityCases) {
          final slug = entry['CategorySlug'] as String;
          final category = find.byKey(Key('map_category_$slug'));
          await tester.ensureVisible(category);
          await tester.tap(category);
          await waitFor(
            () =>
                !container.read(mapBusinessesProvider).isLoading &&
                container
                    .read(mapBusinessesProvider)
                    .items
                    .any((business) => business.id == entry['BusinessID']),
            'Nearby category $slug did not load its $city listing.',
          );
          expect(
            container
                .read(mapBusinessesProvider)
                .items
                .every((business) => business.categorySlug == slug),
            isTrue,
            reason: 'Nearby category $slug returned mixed results in $city.',
          );
        }

        final lastCase = cityCases.last;
        await tester.tap(find.byKey(const ValueKey('nearby_list_view_toggle')));
        await waitFor(
          () => find
              .byKey(ValueKey('nearby_result_${lastCase['BusinessID']}'))
              .evaluate()
              .isNotEmpty,
          'Nearby result list did not show the filtered ${lastCase['City']} listing.',
        );
        debugPrint('PASS customer discovery and 19 Nearby filters: $city');
      }

      apiClient.dio.options.headers.remove('Authorization');
    } finally {
      apiClient.dio.options.headers.remove('Authorization');
      container.dispose();
    }
  });
}

class _DiscoveryAuthNotifier extends AuthNotifier {
  _DiscoveryAuthNotifier() : super.forTesting();

  @override
  Future<bool> verifyOTP(String phone, String otpCode) async {
    try {
      final response = await apiClient.post(
        '/auth/otp/verify',
        data: {'phone_e164': phone, 'otp_code': otpCode},
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      if (!user.roles.contains('customer')) return false;
      state = AuthState(
        user: user,
        accessToken: data['access_token'] as String,
        activeRole: 'customer',
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
