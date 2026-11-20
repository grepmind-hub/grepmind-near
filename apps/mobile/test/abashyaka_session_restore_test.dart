import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/constants/app_constants.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';

AppUser account(String role, {String? status}) => AppUser(
  id: 'synthetic-entry-user',
  phoneE164: '+919990000171',
  status: 'active',
  preferredLanguage: 'en',
  roles: [role],
  riderStatus: status,
);

void cache(AppUser user, String role) {
  FlutterSecureStorage.setMockInitialValues({
    AppConstants.accessTokenKey: 'widget-test-session',
    AppConstants.userKey: jsonEncode(user.toJson()),
    AppConstants.activeRoleKey: role,
  });
}

Future<void> finishRestore(WidgetTester tester, AuthNotifier auth) async {
  for (var i = 0; i < 20 && auth.state.isLoading; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(auth.state.isLoading, isFalse);
}

void main() {
  setUpAll(() => apiClient.init());

  setUp(() {
    apiClient.dio.interceptors.clear();
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final role in ['customer', 'merchant', 'rider']) {
    testWidgets('verified $role restores without requesting OTP', (
      tester,
    ) async {
      final user = account(role, status: role == 'rider' ? 'approved' : null);
      cache(user, role);
      final requests = <String>[];
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.path);
            handler.resolve(
              Response(requestOptions: options, data: {'data': user.toJson()}),
            );
          },
        ),
      );
      final auth = AuthNotifier();
      addTearDown(auth.dispose);
      await finishRestore(tester, auth);
      expect(auth.state.activeRole, role);
      expect(requests, ['/me']);
    });
  }

  for (final role in ['merchant', 'rider']) {
    testWidgets('offline startup cannot restore cached $role privilege', (
      tester,
    ) async {
      cache(account(role, status: 'approved'), role);
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          ),
        ),
      );
      final auth = AuthNotifier();
      addTearDown(auth.dispose);
      await finishRestore(tester, auth);
      expect(auth.state.activeRole, isNull);
    });
  }

  testWidgets('offline Customer retains existing restoration policy', (
    tester,
  ) async {
    cache(account('customer'), 'customer');
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        ),
      ),
    );
    final auth = AuthNotifier();
    addTearDown(auth.dispose);
    await finishRestore(tester, auth);
    expect(auth.state.activeRole, 'customer');
  });

  testWidgets('rejected session cannot restore Merchant mode', (tester) async {
    cache(account('merchant'), 'merchant');
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
          ),
        ),
      ),
    );
    final auth = AuthNotifier();
    addTearDown(auth.dispose);
    await finishRestore(tester, auth);
    expect(auth.state.activeRole, isNull);
  });

  testWidgets('server-revoked Rider approval overrides saved role', (
    tester,
  ) async {
    cache(account('rider', status: 'approved'), 'rider');
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            data: {'data': account('rider', status: 'suspended').toJson()},
          ),
        ),
      ),
    );
    final auth = AuthNotifier();
    addTearDown(auth.dispose);
    await finishRestore(tester, auth);
    expect(auth.state.activeRole, isNull);
  });

  testWidgets('fresh installation makes no auth request', (tester) async {
    final requests = <String>[];
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options.path);
          handler.reject(DioException(requestOptions: options));
        },
      ),
    );
    final auth = AuthNotifier();
    addTearDown(auth.dispose);
    await finishRestore(tester, auth);
    expect(auth.state.isAuthenticated, isFalse);
    expect(requests, isEmpty);
  });
}
