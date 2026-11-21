import 'package:firebase_core/firebase_core.dart';

/// Public Firebase app identifiers supplied at build time for one environment.
/// Server service-account credentials must never be included in the app.
class FirebaseBuildConfig {
  const FirebaseBuildConfig({
    required this.environment,
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
  });

  factory FirebaseBuildConfig.fromEnvironment() => const FirebaseBuildConfig(
    environment: String.fromEnvironment('FIREBASE_ENVIRONMENT'),
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
  );

  final String environment;
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;

  bool get isEmpty => [
    environment,
    apiKey,
    appId,
    messagingSenderId,
    projectId,
  ].every((value) => value.isEmpty);

  bool get isValid =>
      (environment == 'qa' || environment == 'production') &&
      [
        apiKey,
        appId,
        messagingSenderId,
        projectId,
      ].every((value) => value.isNotEmpty && value == value.trim());

  FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
  );
}

/// Android's Google services plugin supplies the native default app when the
/// selected flavor has a configuration file. Missing configuration is safe.
Future<FirebaseBootstrapStatus> initializeFirebaseFromNative({
  Future<void> Function()? initialize,
}) async {
  try {
    if (initialize != null) {
      await initialize();
    } else {
      await Firebase.initializeApp();
    }
    return FirebaseBootstrapStatus.initialized;
  } catch (_) {
    return FirebaseBootstrapStatus.unconfigured;
  }
}

enum FirebaseBootstrapStatus { unconfigured, initialized, failed }

/// Optional initialization must not block phone login or the rest of the app.
Future<FirebaseBootstrapStatus> initializeFirebase(
  FirebaseBuildConfig config, {
  Future<void> Function(FirebaseOptions)? initialize,
}) async {
  if (!config.isValid) return FirebaseBootstrapStatus.unconfigured;
  try {
    if (initialize != null) {
      await initialize(config.options);
    } else {
      await Firebase.initializeApp(options: config.options);
    }
    return FirebaseBootstrapStatus.initialized;
  } catch (_) {
    // Provider errors can contain configuration details; do not log them.
    return FirebaseBootstrapStatus.failed;
  }
}
