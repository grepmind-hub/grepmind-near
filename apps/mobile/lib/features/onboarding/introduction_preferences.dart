import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A presentation preference, separate from authentication and saved roles.
class IntroductionPreferences {
  const IntroductionPreferences();
  static const _key = 'abashyaka_intro_completed_v1';
  static const _storage = FlutterSecureStorage();

  Future<bool> isComplete() async => await _storage.read(key: _key) == 'true';

  Future<void> complete() => _storage.write(key: _key, value: 'true');
}

final introductionPreferencesProvider = Provider<IntroductionPreferences>(
  (ref) => const IntroductionPreferences(),
);
