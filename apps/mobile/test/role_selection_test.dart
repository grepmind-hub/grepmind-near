import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/screens/profile_screen.dart';

void main() {
  const dummyUser = AppUser(
    id: 'usr-123',
    phoneE164: '+919876543210',
    displayName: 'Test User',
    status: 'active',
    preferredLanguage: 'en',
    roles: ['customer', 'merchant'],
  );

  ProviderContainer containerWithRoles({String activeRole = 'customer'}) {
    return ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) {
          return _MemoryAuthNotifier(
            AuthState(
              user: dummyUser,
              accessToken: 'test-token',
              activeRole: activeRole,
            ),
          );
        }),
      ],
    );
  }

  testWidgets(
    'RoleSelectionScreen renders role options with backend permissions',
    (tester) async {
      final container = containerWithRoles();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RoleSelectionScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select Portal Experience'), findsOneWidget);
      expect(find.text('Welcome to Grepmind Near'), findsOneWidget);
      expect(find.byKey(const ValueKey('role_card_customer')), findsOneWidget);
      expect(find.byKey(const ValueKey('role_card_merchant')), findsOneWidget);
      expect(find.byKey(const ValueKey('role_card_rider')), findsOneWidget);
      expect(find.byKey(const ValueKey('role_card_admin')), findsOneWidget);
      expect(find.text('Requires backend approval'), findsOneWidget);
      expect(find.byKey(const ValueKey('continue_role_btn')), findsOneWidget);
      container.dispose();
    },
  );

  testWidgets('Selecting role cards updates selection', (tester) async {
    final container = containerWithRoles();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RoleSelectionScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Merchant card
    await tester.ensureVisible(
      find.byKey(const ValueKey('role_card_merchant')),
    );
    await tester.tap(find.byKey(const ValueKey('role_card_merchant')));
    await tester.pumpAndSettle();

    // Tap Customer card
    await tester.ensureVisible(
      find.byKey(const ValueKey('role_card_customer')),
    );
    await tester.tap(find.byKey(const ValueKey('role_card_customer')));
    await tester.pumpAndSettle();
    container.dispose();
  });

  testWidgets('Rider mode remains locked without a backend rider role', (
    tester,
  ) async {
    final container = containerWithRoles();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RoleSelectionScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final riderCard = find.byKey(const ValueKey('role_card_rider'));
    await tester.ensureVisible(riderCard);
    await tester.tap(riderCard);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('continue_role_btn')));
    await tester.pumpAndSettle();

    expect(container.read(authProvider).activeRole, 'customer');
    expect(find.textContaining('not authorized'), findsNothing);
    container.dispose();
  });

  testWidgets(
    'ProfileScreen enforces RBAC: hides Merchant Workspace in customer mode',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) {
            return _MemoryAuthNotifier(
              const AuthState(
                user: dummyUser,
                accessToken: 'token-abc',
                activeRole: 'customer',
              ),
            );
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Active Mode is CUSTOMER
      expect(find.text('CUSTOMER'), findsOneWidget);
      // Switch Portal / Experience tile should exist
      expect(find.text('Switch Portal / Experience'), findsOneWidget);
      expect(
        find.textContaining('Available: Customer, Merchant'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Available: Customer, Merchant, Rider'),
        findsNothing,
      );
      // Merchant Workspace should NOT be present in customer mode
      expect(find.text('Merchant Workspace'), findsNothing);
    },
  );

  testWidgets(
    'ProfileScreen shows Merchant Workspace when activeRole is merchant',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) {
            return _MemoryAuthNotifier(
              const AuthState(
                user: dummyUser,
                accessToken: 'token-abc',
                activeRole: 'merchant',
              ),
            );
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Active Mode is MERCHANT
      expect(find.text('MERCHANT'), findsOneWidget);
      // Merchant Workspace should now be visible
      expect(find.text('Merchant Workspace'), findsOneWidget);
    },
  );
}

class _MemoryAuthNotifier extends AuthNotifier {
  _MemoryAuthNotifier(AuthState initialState) : super.forTesting() {
    state = initialState;
  }

  @override
  Future<AppUser?> refreshCurrentUser() async => state.user;

  @override
  Future<bool> setActiveRole(String role) async {
    final user = state.user;
    final permitted = switch (role) {
      'customer' => user?.roles.contains('customer') ?? false,
      'merchant' =>
        user != null &&
            (user.roles.contains('merchant') ||
                user.roles.contains('professional')),
      'rider' => user?.roles.contains('rider') ?? false,
      'admin' => user?.roles.contains('admin') ?? false,
      _ => false,
    };
    if (!permitted) return false;
    state = state.copyWith(activeRole: role);
    return true;
  }
}
