import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:integration_test/integration_test.dart';

/// Uses only disposable fixtures created by scripts/merchant_ui_injection.ps1.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer profile/catalog views appear in merchant dashboard', (
    tester,
  ) async {
    const encoded = String.fromEnvironment('UI_FIXTURES_GZIP');
    if (encoded.isEmpty) {
      throw StateError(
        'Run scripts/merchant_ui_injection.ps1 with Scenario Analytics.',
      );
    }
    final manifest = jsonDecode(
      utf8.decode(GZipCodec().decode(base64Decode(encoded))),
    ) as Map<String, dynamic>;
    final cases = (manifest['Cases'] as List).cast<Map<String, dynamic>>();
    final runId = manifest['Run'] as String;
    apiClient.init();
    apiClient.dio.interceptors.clear();
    final tokens = <String, Map<String, dynamic>>{};

    Future<Map<String, dynamic>> login(String phone, String role) async {
      final cached = tokens[phone];
      if (cached != null) return cached;
      apiClient.dio.options.headers.remove('Authorization');
      final otp = await apiClient.post(
        '/auth/otp/request',
        data: {'phone_e164': phone},
      );
      final code = otp.data['data']['otp_code'] as String?;
      if (code == null) throw StateError('Local OTP provider is required.');
      final response = await apiClient.post(
        '/auth/otp/verify',
        data: {'phone_e164': phone, 'otp_code': code},
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      expect((user['roles'] as List).contains(role), isTrue);
      final result = <String, dynamic>{
        'token': data['access_token'] as String,
        'user': user,
      };
      tokens[phone] = result;
      return result;
    }

    Future<void> waitFor(bool Function() predicate, String message) async {
      for (var attempt = 0; attempt < 300; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (predicate()) return;
      }
      fail(message);
    }

    for (final city in const ['Cuttack', 'Jajpur']) {
      final entry = cases.firstWhere(
        (item) => item['City'] == city && item['CategorySlug'] == 'grocery',
      );
      final businessId = entry['BusinessID'] as String;
      final merchant = await login(entry['Phone'] as String, 'merchant');
      apiClient.dio.options.headers['Authorization'] =
          'Bearer ${merchant['token']}';
      final productName = 'QA analytics catalog ${runId.substring(0, 8)} $city';
      await apiClient.post(
        '/merchant/products',
        data: {
          'name': productName,
          'description': 'Temporary published catalog entry for analytics QA.',
          'price': 150,
          'stock_status': 'in_stock',
          'is_published': true,
        },
      );
      final customer = await login(
        manifest['CustomerPhone'] as String,
        'customer',
      );
      final customerUser = AppUser.fromJson(
        customer['user'] as Map<String, dynamic>,
      );
      apiClient.dio.options.headers['Authorization'] =
          'Bearer ${customer['token']}';

      final auth = _InjectedAuthNotifier(customerUser);
      final customerContainer = ProviderContainer(
        overrides: [authProvider.overrideWith((ref) => auth)],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: customerContainer,
            child: MaterialApp(
              home: BusinessDetailScreen(businessId: businessId),
            ),
          ),
        );
        await waitFor(
          () => customerContainer.read(businessDetailProvider).detail != null,
          '$city customer business profile did not load',
        );
        expect(
          customerContainer
              .read(businessDetailProvider)
              .products
              .map((product) => product.name),
          contains(productName),
        );
        final productTab = find.byKey(const Key('business_catalog_tab'));
        await tester.ensureVisible(productTab);
        await tester.tap(productTab);
        await tester.pumpAndSettle();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        customerContainer.dispose();
      }

      apiClient.dio.options.headers['Authorization'] =
          'Bearer ${merchant['token']}';
      Map<String, dynamic> summary = {};
      for (var attempt = 0; attempt < 20; attempt++) {
        final response = await apiClient.get(
          '/merchant/analytics/summary',
          queryParameters: {'business_id': businessId},
        );
        summary = response.data['data'] as Map<String, dynamic>;
        if (summary['profile_views_30d'] == 1 &&
            summary['product_catalog_views_30d'] == 1) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(summary['profile_views_30d'], 1, reason: city);
      expect(summary['product_catalog_views_30d'], 1, reason: city);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MerchantWorkspaceScreen()),
        ),
      );
      final profileViews = find.byKey(
        const Key('merchant_view_metric_business_profile'),
      );
      await waitFor(
        () =>
            profileViews.evaluate().isNotEmpty &&
            tester.widget<Text>(profileViews).data == '1',
        '$city merchant dashboard did not show profile views',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('merchant_view_metric_product_catalog')),
            )
            .data,
        '1',
      );
      debugPrint('PASS merchant customer view analytics: $city');
    }
    tokens.clear();
    apiClient.dio.options.headers.remove('Authorization');
  });
}

class _InjectedAuthNotifier extends AuthNotifier {
  _InjectedAuthNotifier(AppUser user) : super() {
    state = AuthState(user: user);
  }
}
