import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';

void main() {
  test('Search forwards selected city and category without duplicating results', () async {
    apiClient.init();
    apiClient.dio.interceptors.clear();
    const city = 'Selected test city';
    const category = 'test-category';
    apiClient.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.queryParameters['city'], city);
      expect(request.queryParameters['category_slug'], category);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': [{'id': 'test-id', 'name': 'Test listing', 'category_slug': category, 'city': city, 'address_text': city}],
        'meta': <String, dynamic>{},
      }));
    }));
    final notifier = BusinessesNotifier();
    addTearDown(notifier.dispose);
    await notifier.search(query: '', city: city, categorySlug: category);
    expect(notifier.state.error, isNull);
    expect(notifier.state.items.length, 1);
    expect(notifier.state.items.single.city, city);
    await notifier.search(query: '', city: city, categorySlug: category);
    expect(notifier.state.items.length, 1);
  });
}
