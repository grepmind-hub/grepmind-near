import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:integration_test/integration_test.dart';

/// Exercises real merchant request/profile APIs and widgets using disposable
/// local fixture accounts prepared by scripts/merchant_ui_injection.ps1.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('merchant workspace requests and profile work in both cities', (
    tester,
  ) async {
    const encoded = String.fromEnvironment('UI_FIXTURES_GZIP');
    if (encoded.isEmpty) {
      throw StateError(
        'Run scripts/merchant_ui_injection.ps1 with Scenario Workspace.',
      );
    }
    final manifest = jsonDecode(
      utf8.decode(GZipCodec().decode(base64Decode(encoded))),
    ) as Map<String, dynamic>;
    final cases = (manifest['Cases'] as List).cast<Map<String, dynamic>>();
    apiClient.init();
    apiClient.dio.interceptors.clear();
    final tokens = <String, String>{};

    Future<void> waitFor(bool Function() predicate, String message) async {
      for (var attempt = 0; attempt < 300; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (predicate()) return;
      }
      fail(message);
    }

    Future<String> login(String phone, String role) async {
      final existing = tokens[phone];
      if (existing != null) return existing;
      apiClient.dio.options.headers.remove('Authorization');
      final otp = await apiClient.post(
        '/auth/otp/request',
        data: {'phone_e164': phone},
      );
      final code = otp.data['data']['otp_code'] as String?;
      if (code == null) throw StateError('Local OTP provider is required.');
      final session = await apiClient.post(
        '/auth/otp/verify',
        data: {'phone_e164': phone, 'otp_code': code},
      );
      final user = session.data['data']['user'] as Map<String, dynamic>;
      expect((user['roles'] as List).contains(role), isTrue);
      final token = session.data['data']['access_token'] as String;
      tokens[phone] = token;
      return token;
    }

    final runId = manifest['Run'] as String;
    for (final city in const ['Cuttack', 'Jajpur']) {
      final entry = cases.firstWhere(
        (candidate) =>
            candidate['City'] == city && candidate['CategorySlug'] == 'plumber',
      );
      final businessId = entry['BusinessID'] as String;
      final merchantToken = await login(entry['Phone'] as String, 'merchant');
      apiClient.dio.options.headers['Authorization'] = 'Bearer $merchantToken';
      final serviceResponse = await apiClient.post(
        '/merchant/services',
        queryParameters: {'business_id': businessId},
        data: {
          'name': 'QA workspace plumbing service ${runId.substring(0, 8)}',
          'description':
              'Temporary service for merchant workspace E2E validation.',
          'indicative_price_min': 300,
          'indicative_price_max': 1200,
          'is_active': true,
        },
      );
      final serviceId = serviceResponse.data['data']['id'] as String;
      final customerToken = await login(
        manifest['CustomerPhone'] as String,
        'customer',
      );
      apiClient.dio.options.headers['Authorization'] = 'Bearer $customerToken';
      final description = 'QA workspace request ${runId.substring(0, 8)} $city';
      await apiClient.post(
        '/businesses/$businessId/requests',
        data: {'service_id': serviceId, 'description': description},
      );
      apiClient.dio.options.headers['Authorization'] = 'Bearer $merchantToken';

      final location = LocationNotifier()
        ..setLocation(
          AppLocation(
            cityName: city,
            latitude: (entry['Latitude'] as num).toDouble(),
            longitude: (entry['Longitude'] as num).toDouble(),
          ),
        );
      final container = ProviderContainer(
        overrides: [appLocationProvider.overrideWith((ref) => location)],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: MerchantWorkspaceScreen()),
          ),
        );
        await waitFor(
          () => container
              .read(merchantProvider)
              .items
              .any((item) => item.description == description),
          '$city request did not load into the merchant workspace',
        );

        final viewRequests = find.byKey(const Key('merchant_view_requests'));
        await tester.ensureVisible(viewRequests);
        await tester.tap(viewRequests);
        await waitFor(
          () => find.text(description).evaluate().isNotEmpty,
          '$city View Requests shortcut did not open the request',
        );
        final accept = find.widgetWithText(OutlinedButton, 'Accept');
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        await waitFor(
          () => container
              .read(merchantProvider)
              .items
              .any(
                (item) =>
                    item.description == description &&
                    item.status == 'accepted',
              ),
          '$city request did not update to accepted through the UI',
        );
        final requests = await apiClient.get(
          '/merchant/requests',
          queryParameters: {'business_id': businessId},
        );
        final rows = (requests.data['data']['requests'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          rows.any(
            (item) =>
                item['description'] == description &&
                item['status'] == 'accepted',
          ),
          isTrue,
        );

        final requestId =
            rows.singleWhere((item) => item['description'] == description)['id']
                as String;
        final startWork = find.byKey(Key('merchant_start_request_$requestId'));
        await tester.ensureVisible(startWork);
        await tester.tap(startWork);
        await waitFor(
          () => container
              .read(merchantProvider)
              .items
              .any(
                (item) =>
                    item.description == description &&
                    item.status == 'in_progress',
              ),
          '$city request did not transition to in progress through the UI',
        );
        final completeWork = find.byKey(
          Key('merchant_complete_request_$requestId'),
        );
        await tester.ensureVisible(completeWork);
        await tester.tap(completeWork);
        await waitFor(
          () => container
              .read(merchantProvider)
              .items
              .any(
                (item) =>
                    item.description == description &&
                    item.status == 'completed',
              ),
          '$city request did not complete through the UI',
        );
        final completedRequests = await apiClient.get(
          '/merchant/requests',
          queryParameters: {'business_id': businessId},
        );
        final completedRows =
            (completedRequests.data['data']['requests'] as List)
                .cast<Map<String, dynamic>>();
        expect(
          completedRows.singleWhere(
            (item) => item['id'] == requestId,
          )['status'],
          'completed',
        );
        await expectLater(
          apiClient.patch(
            '/merchant/requests/$requestId/status',
            data: {'status': 'accepted'},
          ),
          throwsA(isA<DioException>()),
        );

        await tester.tap(find.text('Dashboard').first);
        await tester.pumpAndSettle();
        final editShortcut = find.byKey(const Key('merchant_edit_profile'));
        await tester.ensureVisible(editShortcut);
        await tester.tap(editShortcut);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('merchant_edit_business_profile')),
        );
        await tester.tap(
          find.byKey(const Key('merchant_edit_business_profile')),
        );
        await tester.pumpAndSettle();

        final updatedName = 'QA Workspace ${runId.substring(0, 8)} $city';
        final nameField = find.byKey(const Key('merchant_profile_name'));
        await tester.ensureVisible(nameField);
        await tester.enterText(nameField, updatedName);
        final saveProfile = find.byKey(const Key('merchant_save_profile'));
        await tester.ensureVisible(saveProfile);
        await tester.tap(saveProfile);
        await waitFor(
          () =>
              container.read(merchantProfileProvider('')).profile?['name'] ==
              updatedName,
          '$city profile edit did not save through the workspace UI',
        );
        final savedProfile = await apiClient.get(
          '/merchant/profile',
          queryParameters: {'business_id': businessId},
        );
        expect(savedProfile.data['data']['name'], updatedName);
        debugPrint('PASS merchant workspace requests and profile: $city');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      }
    }
    tokens.clear();
    apiClient.dio.options.headers.remove('Authorization');
  });
}
