import 'package:dio/dio.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';

void main() {
  setUpAll(() => apiClient.init());
  setUp(() => apiClient.dio.interceptors.clear());
  test(
    'Search forwards selected city and category without duplicating results',
    () async {
      const city = 'Selected test city';
      const category = 'test-category';
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.queryParameters['city'], city);
            expect(request.queryParameters['category_slug'], category);
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: {
                  'data': [
                    {
                      'id': 'test-id',
                      'name': 'Test listing',
                      'category_slug': category,
                      'city': city,
                      'address_text': city,
                    },
                  ],
                  'meta': <String, dynamic>{},
                },
              ),
            );
          },
        ),
      );
      final notifier = BusinessesNotifier();
      addTearDown(notifier.dispose);
      await notifier.search(query: '', city: city, categorySlug: category);
      expect(notifier.state.error, isNull);
      expect(notifier.state.items.length, 1);
      expect(notifier.state.items.single.city, city);
      await notifier.search(query: '', city: city, categorySlug: category);
      expect(notifier.state.items.length, 1);
    },
  );

  test(
    'Nearby forwards filters and ignores a late response from a previous city',
    () async {
      final firstRequest =
          Completer<(RequestOptions, RequestInterceptorHandler)>();
      final secondRequest =
          Completer<(RequestOptions, RequestInterceptorHandler)>();
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.queryParameters['limit'], 50);
            expect(options.queryParameters['category_slug'], 'test-category');
            (options.queryParameters['city'] == 'Cuttack'
                    ? firstRequest
                    : secondRequest)
                .complete((options, handler));
          },
        ),
      );
      final notifier = BusinessesNotifier();
      addTearDown(notifier.dispose);
      final old = notifier.nearby(
        lat: 0,
        lng: 0,
        city: 'Cuttack',
        categorySlug: 'test-category',
      );
      final first = await firstRequest.future;
      final current = notifier.nearby(
        lat: 1,
        lng: 1,
        city: 'Jajpur',
        categorySlug: 'test-category',
      );
      final second = await secondRequest.future;
      Response<dynamic> result(RequestOptions options, String city) => Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'data': [
            {
              'id': city,
              'name': city,
              'category_slug': 'test-category',
              'city': city,
            },
          ],
          'meta': <String, dynamic>{},
        },
      );
      second.$2.resolve(result(second.$1, 'Jajpur'));
      await current;
      expect(notifier.state.items.single.city, 'Jajpur');
      first.$2.resolve(result(first.$1, 'Cuttack'));
      await old;
      expect(notifier.state.items.single.city, 'Jajpur');
    },
  );
}
