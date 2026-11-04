import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/booking_scheduler_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_availability_screen.dart';
import 'package:grepmind_mobile/core/screens/service_request_screen.dart';
import 'package:grepmind_mobile/core/screens/service_request_status_screen.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Uses generated local merchant/customer identities and cleanup-owned records.
/// Run with scripts/merchant_ui_injection.ps1 -Scenario Availability.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('merchant manages local slots and customer books one on device', (
    tester,
  ) async {
    const encoded = String.fromEnvironment('UI_FIXTURES_GZIP');
    if (encoded.isEmpty) {
      throw StateError(
        'Run the availability scenario to generate owned fixtures.',
      );
    }
    final fixture = jsonDecode(
      utf8.decode(GZipCodec().decode(base64Decode(encoded))),
    ) as Map<String, dynamic>;
    final cases = (fixture['Cases'] as List).cast<Map<String, dynamic>>();
    final customerPhone = fixture['CustomerPhone'] as String?;
    if (cases.isEmpty || customerPhone == null || customerPhone.isEmpty) {
      throw StateError('The local fixture requires a merchant and customer.');
    }
    final merchantFixture = cases.firstWhere(
      (entry) =>
          entry['City'] == 'Cuttack' && entry['CategorySlug'] == 'plumber',
      orElse: () => cases.first,
    );
    final businessId = merchantFixture['BusinessID'] as String;
    apiClient.init();
    apiClient.dio.interceptors.clear();

    Future<Map<String, dynamic>> login(String phone, String role) async {
      apiClient.dio.options.headers.remove('Authorization');
      final otpResponse = await apiClient.post(
        '/auth/otp/request',
        data: {'phone_e164': phone},
      );
      final otp =
          (otpResponse.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final code = otp['otp_code'] as String?;
      if (code == null || code.isEmpty) {
        throw StateError('The local OTP provider is not available.');
      }
      final response = await apiClient.post(
        '/auth/otp/verify',
        data: {'phone_e164': phone, 'otp_code': code},
      );
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      if (!(user['roles'] as List<dynamic>).contains(role)) {
        throw StateError('Generated login did not receive the $role role.');
      }
      return {'token': data['access_token'] as String, 'user': user};
    }

    Future<void> waitFor(bool Function() predicate, String message) async {
      for (var attempt = 0; attempt < 300; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (predicate()) return;
      }
      fail(message);
    }

    final merchantSession = await login(
      merchantFixture['Phone'] as String,
      'merchant',
    );
    final merchantToken = merchantSession['token'] as String;
    apiClient.dio.options.headers['Authorization'] = 'Bearer $merchantToken';

    final otherBusiness = cases.firstWhere(
      (entry) => entry['BusinessID'] != businessId,
    );
    final otherMerchantSession = await login(
      otherBusiness['Phone'] as String,
      'merchant',
    );
    final otherMerchantToken = otherMerchantSession['token'] as String;
    apiClient.dio.options.headers['Authorization'] =
        'Bearer $otherMerchantToken';
    await expectLater(
      apiClient.get('/merchant/businesses/$businessId/availability'),
      throwsA(isA<DioException>()),
    );
    apiClient.dio.options.headers['Authorization'] = 'Bearer $merchantToken';

    final hours = List.generate(
      7,
      (weekday) => {
        'weekday': weekday,
        'opens_at': '00:00',
        'closes_at': '23:59',
        'is_closed': false,
      },
    );
    await apiClient.put('/merchant/operating-hours', data: {'hours': hours});
    final serviceResponse = await apiClient.post(
      '/merchant/services',
      data: {
        'name': 'Appointment ${fixture['Run']}',
        'description': 'Temporary local emulator validation service',
        'indicative_price_min': 500,
        'is_active': true,
      },
    );
    final serviceData =
        (serviceResponse.data as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final service = Service(
      id: serviceData['id'] as String,
      businessId: businessId,
      name: 'Appointment ${fixture['Run']}',
      indicativePriceMin: 500,
    );

    final businessNow = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final appointmentDate = DateTime(
      businessNow.year,
      businessNow.month,
      businessNow.day,
    ).add(const Duration(days: 1));
    final startHour = (businessNow.hour % 12) + 8;
    final slotAStart = '${startHour.toString().padLeft(2, '0')}:00';
    final slotAEnd = '${startHour.toString().padLeft(2, '0')}:30';
    final slotBHour = startHour + 1;
    final slotBStart = '${slotBHour.toString().padLeft(2, '0')}:00';
    final slotBEnd = '${slotBHour.toString().padLeft(2, '0')}:30';
    final localDate = DateFormat('yyyy-MM-dd').format(appointmentDate);
    Future<String> createSlot(String startsAt, String endsAt) async {
      final response = await apiClient
          .post(
            '/merchant/businesses/$businessId/availability-slots',
            data: {
              'date': localDate,
              'starts_at': startsAt,
              'ends_at': endsAt,
              'capacity': 1,
            },
          )
          .catchError((Object error) {
            final data = (error as dynamic).response?.data;
            throw StateError('Slot creation was rejected: $data');
          });
      final data =
          (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      return data['id'] as String;
    }

    final slotA = await createSlot(slotAStart, slotAEnd);
    final slotB = await createSlot(slotBStart, slotBEnd);
    await expectLater(
      apiClient.post(
        '/merchant/businesses/$businessId/availability-slots',
        data: {
          'date': localDate,
          'starts_at': slotAStart,
          'ends_at': slotAEnd,
          'capacity': 1,
        },
      ),
      throwsA(isA<DioException>()),
    );
    String displayMerchantTime(String value) {
      final parts = value.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      final period = hour < 12 ? 'AM' : 'PM';
      return '$displayHour:$minute $period';
    }

    final slotARange =
        '${displayMerchantTime(slotAStart)} – ${displayMerchantTime(slotAEnd)}';
    final slotBLabel = DateFormat('hh:mm a')
        .format(DateTime.parse('2000-01-01T$slotBStart:00'));

    final profileCheck = await apiClient.get('/merchant/profile');
    final profileData =
        (profileCheck.data as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    expect(profileData['id'], businessId);
    final availabilityCheck = await apiClient.get(
      '/merchant/businesses/$businessId/availability',
      queryParameters: {'from': localDate, 'to': localDate},
    );
    expect(
      ((availabilityCheck.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>)['slots'],
      isA<List<dynamic>>(),
    );

    // Real merchant availability screen: select the date and close one slot.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: MerchantAvailabilityScreen()),
      ),
    );
    final merchantDayLabel = DateFormat('E')
        .format(appointmentDate)
        .substring(0, 2);
    await waitFor(
      () =>
          find.text(merchantDayLabel).evaluate().isNotEmpty ||
          find.text('Retry').evaluate().isNotEmpty,
      'Merchant date picker did not load.',
    );
    if (find.text('Retry').evaluate().isNotEmpty) {
      fail('Merchant availability UI entered its error state.');
    }
    await tester.tap(find.text(merchantDayLabel));
    await tester.pumpAndSettle();
    await waitFor(
      () => find.text(slotARange).evaluate().isNotEmpty,
      'Merchant could not select the appointment date.',
    );
    final slotCard = find.ancestor(
      of: find.text(slotARange),
      matching: find.byType(PremiumCard),
    );
    await tester.tap(
      find.descendant(of: slotCard, matching: find.byTooltip('Slot actions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close slot'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 1 booked • Closed'), findsOneWidget);
    final merchantSlots = await apiClient.get(
      '/merchant/businesses/$businessId/availability',
      queryParameters: {'from': localDate, 'to': localDate},
    );
    final merchantData =
        (merchantSlots.data as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final slotRows = (merchantData['slots'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      slotRows.singleWhere((slot) => slot['id'] == slotA)['status'],
      'closed',
    );

    // A date exception closes the full local date and releases all open slots.
    final closedDate = appointmentDate.add(const Duration(days: 1));
    final closedDateKey = DateFormat('yyyy-MM-dd').format(closedDate);
    final closedSlot = await apiClient.post(
      '/merchant/businesses/$businessId/availability-slots',
      data: {
        'date': closedDateKey,
        'starts_at': slotAStart,
        'ends_at': slotAEnd,
        'capacity': 1,
      },
    );
    final closedSlotId = closedSlot.data['data']['id'] as String;
    await apiClient.put(
      '/merchant/businesses/$businessId/availability-exceptions',
      data: {
        'date': closedDateKey,
        'is_closed': true,
        'note': 'QA closed-date validation',
      },
    );
    final closedDayAvailability = await apiClient.get(
      '/businesses/$businessId/availability',
      queryParameters: {
        'from': '${closedDateKey}T00:00:00+05:30',
        'to': '${closedDateKey}T23:59:59+05:30',
      },
    );
    final closedDayRows = closedDayAvailability.data['data'] as List<dynamic>;
    expect(
      closedDayRows.cast<Map<String, dynamic>>().any(
        (slot) => slot['id'] == closedSlotId,
      ),
      isFalse,
    );
    final customerSession = await login(customerPhone, 'customer');
    final customerToken = customerSession['token'] as String;
    apiClient.dio.options.headers['Authorization'] = 'Bearer $customerToken';
    await expectLater(
      apiClient.post(
        '/businesses/$businessId/requests',
        data: {
          'service_id': service.id,
          'slot_id': closedSlotId,
          'requested_for': '${closedDateKey}T$slotAStart:00+05:30',
          'description': 'Closed-date QA booking rejection',
        },
      ),
      throwsA(isA<DioException>()),
    );

    // A failed request submission must remain on the form, not show receipt.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ServiceRequestScreen(
            businessId: 'missing-${fixture['Run']}',
            businessName: 'QA unavailable listing',
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField).last,
      'Request submission failure validation',
    );
    await tester.tap(find.text('Submit request'));
    await waitFor(
      () => find
          .text('Could not submit your request. Please try again.')
          .evaluate()
          .isNotEmpty,
      'Failed service request did not show a recoverable error.',
    );
    expect(find.byType(ServiceRequestStatusScreen), findsNothing);

    // Real customer scheduler: book the remaining slot through the API-backed UI.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: BookingSchedulerScreen(
            businessId: businessId,
            businessName: merchantFixture['ProductName'] as String,
            selectedService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final customerDayLabel = DateFormat('EEE')
        .format(appointmentDate)
        .toUpperCase();
    await waitFor(
      () => find.text(customerDayLabel).evaluate().isNotEmpty,
      'Customer date picker did not load.',
    );
    await tester.tap(find.text(customerDayLabel).first);
    await waitFor(
      () => find.text(slotBLabel).evaluate().isNotEmpty,
      'Customer scheduler did not show the merchant-local slot.',
    );
    await tester.ensureVisible(find.text(slotBLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(slotBLabel));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      '${merchantFixture['City']} QA appointment address',
    );
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && (widget.data?.startsWith('Book ') ?? false),
      ),
    );
    await waitFor(
      () => find.text('Booking Requested!').evaluate().isNotEmpty,
      'Customer booking did not complete successfully in the app.',
    );

    final customerRequests = await apiClient.get('/customer/requests');
    final requestData =
        (customerRequests.data as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final requests = (requestData['requests'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      requests.any(
        (request) =>
            request['business_id'] == businessId &&
            request['requested_for'] != null,
      ),
      isTrue,
    );
    apiClient.dio.options.headers['Authorization'] = 'Bearer $merchantToken';
    final finalAvailability = await apiClient.get(
      '/merchant/businesses/$businessId/availability',
      queryParameters: {'from': localDate, 'to': localDate},
    );
    final finalData =
        (finalAvailability.data as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final bookedSlot = (finalData['slots'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((slot) => slot['id'] == slotB);
    expect(bookedSlot['booked_count'], 1);
    expect(finalData['time_zone'], 'Asia/Kolkata');
  });
}
