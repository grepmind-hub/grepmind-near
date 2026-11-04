import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/service_request_status_screen.dart';
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
      await apiClient.put(
        '/merchant/operating-hours',
        data: {
          'hours': List.generate(
            7,
            (weekday) => {
              'weekday': weekday,
              'opens_at': '00:00',
              'closes_at': '23:59',
              'is_closed': false,
            },
          ),
        },
      );
      final businessLocalNow = DateTime.now().toUtc().add(
        const Duration(hours: 5, minutes: 30),
      );
      final appointmentDate = DateTime(
        businessLocalNow.year,
        businessLocalNow.month,
        businessLocalNow.day,
      ).add(const Duration(days: 1));
      final appointmentDateKey = DateFormat('yyyy-MM-dd')
          .format(appointmentDate);
      Future<String> createAppointmentSlot(String start, String end) async {
        final response = await apiClient.post(
          '/merchant/businesses/$businessId/availability-slots',
          data: {
            'date': appointmentDateKey,
            'starts_at': start,
            'ends_at': end,
            'capacity': 1,
          },
        );
        return response.data['data']['id'] as String;
      }

      final originalSlotId = await createAppointmentSlot('10:00', '10:30');
      final replacementSlotId = await createAppointmentSlot('12:00', '12:30');
      final customerToken = await login(
        manifest['CustomerPhone'] as String,
        'customer',
      );
      apiClient.dio.options.headers['Authorization'] = 'Bearer $customerToken';
      final description = 'QA workspace request ${runId.substring(0, 8)} $city';
      await apiClient.post(
        '/businesses/$businessId/requests',
        data: {
          'service_id': serviceId,
          'slot_id': originalSlotId,
          'description': description,
        },
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
                item['status'] == 'accepted' &&
                item['slot_id'] == originalSlotId &&
                item['requested_local_date'] == appointmentDateKey,
          ),
          isTrue,
        );

        final requestId =
            rows.singleWhere((item) => item['description'] == description)['id']
                as String;
        final initialAvailability = await apiClient.get(
          '/merchant/businesses/$businessId/availability',
          queryParameters: {
            'from': appointmentDateKey,
            'to': appointmentDateKey,
          },
        );
        final initialSlots = (initialAvailability.data['data']['slots'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          initialSlots.any(
            (slot) =>
                slot['id'] == replacementSlotId &&
                slot['remaining_capacity'] == 1,
          ),
          isTrue,
          reason: 'Expected the replacement slot on $appointmentDateKey',
        );
        final reschedule = find.byKey(
          Key('merchant_reschedule_request_$requestId'),
        );
        await tester.ensureVisible(reschedule);
        await tester.tap(reschedule);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        final replacementOption = find.byKey(
          Key('merchant_reschedule_slot_$replacementSlotId'),
        );
        await tester.ensureVisible(replacementOption);
        await tester.tap(replacementOption);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Icon>(
                find.byKey(
                  Key('merchant_reschedule_selected_$replacementSlotId'),
                ),
              )
              .icon,
          Icons.radio_button_checked,
          reason: 'Selecting the replacement appointment should enable it',
        );
        await tester.tap(find.byKey(const Key('merchant_reschedule_confirm')));
        await tester.pumpAndSettle();
        try {
          await waitFor(
            () => container
                .read(merchantProvider)
                .items
                .any(
                  (item) =>
                      item.description == description &&
                      item.status == 'rescheduled' &&
                      item.slotId == replacementSlotId,
                ),
            '$city merchant could not propose the replacement appointment',
          );
        } catch (_) {
          final latestRequests = await apiClient.get(
            '/merchant/requests',
            queryParameters: {'business_id': businessId},
          );
          final latestRows = (latestRequests.data['data']['requests'] as List)
              .cast<Map<String, dynamic>>();
          final latest = latestRows.singleWhere(
            (item) => item['id'] == requestId,
          );
          final snackbars = tester
              .widgetList<SnackBar>(find.byType(SnackBar))
              .map(
                (snack) => snack.content is Text
                    ? (snack.content as Text).data
                    : snack.content.runtimeType.toString(),
              )
              .toList();
          debugPrint(
            'RESCHEDULE_DIAGNOSTIC server=${latest['status']}/${latest['slot_id']} '
            'local=${container.read(merchantProvider).items.where((item) => item.id == requestId).map((item) => '${item.status}/${item.slotId}').toList()} '
            'snackbars=$snackbars',
          );
          rethrow;
        }

        final movedAvailability = await apiClient.get(
          '/merchant/businesses/$businessId/availability',
          queryParameters: {
            'from': appointmentDateKey,
            'to': appointmentDateKey,
          },
        );
        final movedSlots = (movedAvailability.data['data']['slots'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          movedSlots.singleWhere(
            (slot) => slot['id'] == originalSlotId,
          )['booked_count'],
          0,
        );
        expect(
          movedSlots.singleWhere(
            (slot) => slot['id'] == replacementSlotId,
          )['booked_count'],
          1,
        );
        await expectLater(
          apiClient.patch(
            '/merchant/requests/$requestId/status',
            data: {'status': 'accepted'},
          ),
          throwsA(isA<DioException>()),
        );

        final otherMerchant = cases.firstWhere(
          (candidate) => candidate['BusinessID'] != businessId,
        );
        final otherMerchantToken = await login(
          otherMerchant['Phone'] as String,
          'merchant',
        );
        apiClient.dio.options.headers['Authorization'] =
            'Bearer $otherMerchantToken';
        await expectLater(
          apiClient.post('/requests/$requestId/confirm-reschedule'),
          throwsA(isA<DioException>()),
        );
        apiClient.dio.options.headers['Authorization'] =
            'Bearer $customerToken';
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: ServiceRequestStatusScreen(
                requestId: requestId,
                businessName: entry['BusinessName'] as String,
                serviceName: 'QA plumbing service',
                initialStatus: 'accepted',
              ),
            ),
          ),
        );
        await waitFor(
          () => find.text('RESCHEDULED').evaluate().isNotEmpty,
          '$city customer did not receive the proposed time',
        );
        expect(find.text('New Time Proposed'), findsAtLeastNWidgets(1));
        await tester.tap(find.byKey(const Key('customer_confirm_reschedule')));
        await waitFor(
          () => find.text('ACCEPTED').evaluate().isNotEmpty,
          '$city customer could not confirm the replacement time',
        );
        final confirmedRequest = await apiClient.get('/requests/$requestId');
        expect(confirmedRequest.data['data']['status'], 'accepted');
        expect(confirmedRequest.data['data']['slot_id'], replacementSlotId);

        apiClient.dio.options.headers['Authorization'] =
            'Bearer $merchantToken';
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: MerchantWorkspaceScreen()),
          ),
        );
        await container.read(merchantProvider.notifier).loadRequests();
        await waitFor(
          () => container
              .read(merchantProvider)
              .items
              .any(
                (item) =>
                    item.description == description &&
                    item.status == 'accepted',
              ),
          '$city merchant did not receive customer confirmation',
        );
        await tester.tap(find.text('Requests').first);
        await waitFor(
          () => find.text(description).evaluate().isNotEmpty,
          '$city merchant could not reopen the confirmed request',
        );
        final startWork = find.byKey(Key('merchant_start_request_$requestId'));
        await tester.ensureVisible(startWork);
        await tester.pumpAndSettle();
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
        await tester.pumpAndSettle();
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
