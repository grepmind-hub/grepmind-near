import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/merchant_categories_screen.dart';

void main() {
  testWidgets('Category manager saves, reloads, renames, and deletes through API', (tester) async {
    final items = <Map<String, dynamic>>[];
    apiClient.init(baseUrl: 'http://localhost/api/v1');
    apiClient.dio.interceptors.clear();
    apiClient.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'POST') items.add({'id': 'category-1', 'name': request.data['name']});
      if (request.method == 'PATCH') items.single['name'] = request.data['name'];
      if (request.method == 'DELETE') items.clear();
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {'data': items.map((item) => Map<String, dynamic>.from(item)).toList()}));
    }));
    await tester.pumpWidget(const MaterialApp(home: MerchantCategoriesScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Add your first category'), findsOneWidget);
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Electrical');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Electrical'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Supplies');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Supplies'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(items, isEmpty);
    expect(find.textContaining('Add your first category'), findsOneWidget);
  });
}
