import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/home_feed_provider.dart';
import 'package:grepmind_mobile/core/screens/doctor_directory_screen.dart';
import 'package:grepmind_mobile/core/screens/home_screen.dart';
import 'package:grepmind_mobile/core/screens/local_transport_screen.dart';

class _QuietCategoriesNotifier extends CategoriesNotifier {
  @override
  Future<void> load() async {}
}

void main() {
  setUpAll(() => apiClient.init());
  setUp(() => apiClient.dio.interceptors.clear());

  group('Doctor & Medical Facility Integrity Tests (Phase 01F.1)', () {
    testWidgets(
      'DoctorDirectoryScreen renders truthful empty state when no facilities exist',
      (tester) async {
        apiClient.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              if (request.path == '/businesses' &&
                  request.queryParameters['category_slug'] == 'medical') {
                handler.resolve(
                  Response(
                    requestOptions: request,
                    statusCode: 200,
                    data: {'data': <dynamic>[]},
                  ),
                );
                return;
              }
              handler.next(request);
            },
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: DoctorDirectoryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Verified truthful heading & empty state
        expect(find.text('Clinics & Medical Facilities'), findsOneWidget);
        expect(
          find.text('No clinics or medical facilities listed yet'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Doctor consultation schedules are not available in this area yet',
          ),
          findsOneWidget,
        );

        // Verifies zero fictional doctor profiles or booking actions
        expect(find.text('Dr. Visiting Consultant'), findsNothing);
        expect(find.textContaining('Qualification · Specialty'), findsNothing);
        expect(find.text('Booking'), findsNothing);
        expect(find.text('Concept'), findsNothing);
      },
    );

    testWidgets(
      'DoctorDirectoryScreen displays genuine facility data and separates facility verification from doctor claims',
      (tester) async {
        apiClient.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              if (request.path == '/businesses' &&
                  request.queryParameters['category_slug'] == 'medical') {
                handler.resolve(
                  Response(
                    requestOptions: request,
                    statusCode: 200,
                    data: {
                      'data': [
                        {
                          'id': '11111111-1111-1111-1111-111111111111',
                          'name': 'Kuanpal Health Centre',
                          'category_slug': 'medical',
                          'category_name': 'Health Clinic',
                          'address_text': 'Main Road, Kuanpal',
                          'locality': 'Kuanpal',
                          'city': 'Cuttack',
                          'status': 'approved',
                          'verification_status': 'verified',
                          'phone_e164': '+916710000001',
                          'is_open_now': true,
                          'is_synthetic': false,
                        },
                        {
                          'id': '22222222-2222-2222-2222-222222222222',
                          'name': 'Rural Ayurvedic Dispensary',
                          'category_slug': 'medical',
                          'category_name': 'Dispensary',
                          'address_text': 'Chhatia Bazaar',
                          'locality': 'Chhatia',
                          'city': 'Jajpur',
                          'status': 'approved',
                          'verification_status': 'pending',
                          'phone_e164': null,
                          'is_open_now': false,
                          'is_synthetic': false,
                        },
                      ],
                    },
                  ),
                );
                return;
              }
              handler.next(request);
            },
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: DoctorDirectoryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Facility 1: Verified facility with phone
        expect(find.text('Kuanpal Health Centre'), findsOneWidget);
        expect(find.text('Facility Verified'), findsOneWidget);
        expect(find.text('Facility open now'), findsOneWidget);
        expect(find.text('Call Clinic'), findsOneWidget);

        // Facility 2: Unverified facility without phone
        expect(find.text('Rural Ayurvedic Dispensary'), findsOneWidget);
        expect(
          find.text('Facility closed · Check regular hours'),
          findsOneWidget,
        );
        expect(find.text('Contact phone not listed'), findsOneWidget);

        // Safeguard 3: ZERO doctor verification, fictional doctor cards, or booking actions
        expect(find.text('Doctor Verified'), findsNothing);
        expect(find.text('Dr. Visiting Consultant'), findsNothing);
        expect(find.text('Booking'), findsNothing);
      },
    );
  });

  group('Local Transport Integrity Tests (Phase 01F.1)', () {
    testWidgets(
      'LocalTransportScreen excludes repair garages and renders honest empty state',
      (tester) async {
        apiClient.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              if (request.path == '/businesses' &&
                  request.queryParameters['category_slug'] == 'automotive') {
                handler.resolve(
                  Response(
                    requestOptions: request,
                    statusCode: 200,
                    data: {
                      'data': [
                        {
                          'id': '33333333-3333-3333-3333-333333333333',
                          'name': 'Maa Tarini Two-Wheeler Garage',
                          'category_slug': 'automotive',
                          'address_text': 'Station Road, Cuttack',
                          'status': 'approved',
                          'verification_status': 'verified',
                          'phone_e164': '+916719999999',
                          'is_synthetic': false,
                        },
                      ],
                    },
                  ),
                );
                return;
              }
              handler.next(request);
            },
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: LocalTransportScreen())),
        );
        await tester.pumpAndSettle();

        // Safeguard 2: Zero automotive garage promoted as passenger transport
        expect(find.text('Maa Tarini Two-Wheeler Garage'), findsNothing);

        // Honest empty state
        expect(
          find.text('No local transport operators listed yet'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Passenger transport operators and direct driver booking are not yet active',
          ),
          findsOneWidget,
        );

        // Zero Concept badge, zero fake filter chips, zero booking CTA, zero fabricated fare claims
        expect(find.text('Concept'), findsNothing);
        expect(find.text('Auto'), findsNothing);
        expect(find.text('Cab'), findsNothing);
        expect(find.text('Taxi'), findsNothing);
        expect(find.text('Local Trips'), findsNothing);
        expect(find.text('Book'), findsNothing);
        expect(find.textContaining('Verified local rate'), findsNothing);
      },
    );
  });

  group('Home Screen Truthful Subtitles & Category Labels (Phase 01F.1)', () {
    testWidgets(
      'HomeScreen displays truthful category label and truthful subtitles',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeFeedProvider('')
                  .overrideWith((ref) async => const HomeFeed()),
              homeFeedProvider('Cuttack')
                  .overrideWith((ref) async => const HomeFeed()),
              homeFeedProvider('Jajpur')
                  .overrideWith((ref) async => const HomeFeed()),
              categoriesProvider.overrideWith(
                (ref) => _QuietCategoriesNotifier(),
              ),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Category grid has 'Doctors' label
        expect(find.text('Doctors'), findsWidgets);

        // Subtitles are truthful
        expect(
          find.text('Find registered clinics and healthcare centres'),
          findsOneWidget,
        );
        expect(
          find.text('Registered auto-rickshaw and taxi directory'),
          findsOneWidget,
        );

        // Misleading claims are absent
        expect(
          find.text('See doctors, consultation locations and schedules'),
          findsNothing,
        );
        expect(
          find.text('Vehicles, local fares, contact and booking'),
          findsNothing,
        );
      },
    );
  });
}
