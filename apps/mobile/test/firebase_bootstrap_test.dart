import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/notifications/firebase_bootstrap.dart';

void main() {
  test(
    'native initialization remains optional when configuration is absent',
    () async {
      final result = await initializeFirebaseFromNative(
        initialize: () async {
          throw StateError('no native configuration');
        },
      );
      expect(result, FirebaseBootstrapStatus.unconfigured);
    },
  );

  test('native initialization reports success', () async {
    final result = await initializeFirebaseFromNative(initialize: () async {});
    expect(result, FirebaseBootstrapStatus.initialized);
  });
  const valid = FirebaseBuildConfig(
    environment: 'qa',
    apiKey: 'test-key',
    appId: 'test-app',
    messagingSenderId: '123',
    projectId: 'test-project',
  );

  test('missing configuration does not initialize Firebase', () async {
    var calls = 0;
    const missing = FirebaseBuildConfig(
      environment: 'qa',
      apiKey: '',
      appId: 'a',
      messagingSenderId: '123',
      projectId: 'p',
    );
    final result = await initializeFirebase(
      missing,
      initialize: (_) async {
        calls++;
      },
    );
    expect(result, FirebaseBootstrapStatus.unconfigured);
    expect(calls, 0);
  });

  test('valid configuration reaches the initializer', () async {
    String? project;
    final result = await initializeFirebase(
      valid,
      initialize: (options) async {
        project = options.projectId;
      },
    );
    expect(result, FirebaseBootstrapStatus.initialized);
    expect(project, 'test-project');
  });

  test('provider failure does not throw into app startup', () async {
    final result = await initializeFirebase(
      valid,
      initialize: (_) async {
        throw StateError('provider unavailable');
      },
    );
    expect(result, FirebaseBootstrapStatus.failed);
  });

  test('unknown environment and whitespace are rejected', () {
    expect(
      const FirebaseBuildConfig(
        environment: 'dev',
        apiKey: 'a',
        appId: 'b',
        messagingSenderId: 'c',
        projectId: 'd',
      ).isValid,
      isFalse,
    );
    expect(
      const FirebaseBuildConfig(
        environment: 'qa',
        apiKey: ' a',
        appId: 'b',
        messagingSenderId: 'c',
        projectId: 'd',
      ).isValid,
      isFalse,
    );
  });
}
