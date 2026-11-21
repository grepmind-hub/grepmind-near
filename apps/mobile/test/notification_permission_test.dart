import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/notifications/notification_permission.dart';

class FakeGateway implements NotificationPermissionGateway {
  bool? enabled = false;
  bool asked = false;
  bool grant = false;
  int requests = 0;
  @override
  Future<bool?> isEnabled() async => enabled;
  @override
  Future<bool?> request() async {
    requests++;
    enabled = grant;
    return enabled;
  }

  @override
  Future<bool> wasRequested() async => asked;
  @override
  Future<void> markRequested() async {
    asked = true;
  }

  @override
  Future<bool> openSettings() async => true;
}

void main() {
  test(
    'denial does not repeatedly request and a settings change is detected',
    () async {
      final gateway = FakeGateway();
      final manager = NotificationPermissionManager(gateway);
      expect(await manager.status(), NotificationPermissionState.notRequested);
      expect(await manager.requestOnce(), NotificationPermissionState.denied);
      expect(await manager.requestOnce(), NotificationPermissionState.denied);
      expect(gateway.requests, 1);
      gateway.enabled = true;
      expect(await manager.status(), NotificationPermissionState.allowed);
    },
  );
  test('permission grant and unavailable platform are represented', () async {
    final gateway = FakeGateway()..grant = true;
    expect(
      await NotificationPermissionManager(gateway).requestOnce(),
      NotificationPermissionState.allowed,
    );
    gateway.enabled = null;
    expect(
      await NotificationPermissionManager(gateway).status(),
      NotificationPermissionState.unavailable,
    );
  });
}
