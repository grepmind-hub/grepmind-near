import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/rider_application_screen.dart';

void main() {
  setUpAll(() => apiClient.init(baseUrl: 'https://rider.test/api/v1'));
  setUp(() => apiClient.dio.interceptors.clear());

  testWidgets(
    'shows API-backed enabled localities and review checklist state',
    (tester) async {
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.path;
            if (path.endsWith('/rider/localities')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': <Map<String, dynamic>>[
                      {
                        'id': 'kuanpal-id',
                        'name': 'Kuanpal',
                        'district': 'Cuttack',
                      },
                    ],
                  },
                ),
              );
              return;
            }
            if (path.endsWith('/rider/document-requirements')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'data': <dynamic>[]},
                ),
              );
              return;
            }
            if (path.endsWith('/rider/application')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'data': null},
                ),
              );
              return;
            }
            handler.reject(
              DioException(
                requestOptions: options,
                error: 'Unexpected API call',
              ),
            );
          },
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: RiderApplicationScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Become a delivery partner'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(find.text('Kuanpal'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        true,
      );

      await tester.scrollUntilVisible(
        find.textContaining('No document checklist is configured yet.'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('No document checklist is configured yet.'),
        findsOneWidget,
      );
    },
  );
}
