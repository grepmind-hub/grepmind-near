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

  testWidgets('RoleSelectionScreen renders Customer, Merchant, and Admin options', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: RoleSelectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select Portal Experience'), findsOneWidget);
    expect(find.text('Welcome to Grepmind Near'), findsOneWidget);
    expect(find.byKey(const ValueKey('role_card_customer')), findsOneWidget);
    expect(find.byKey(const ValueKey('role_card_merchant')), findsOneWidget);
    expect(find.byKey(const ValueKey('role_card_admin')), findsOneWidget);
    expect(find.byKey(const ValueKey('continue_role_btn')), findsOneWidget);
  });

  testWidgets('Selecting role cards updates selection', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: RoleSelectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Merchant card
    await tester.ensureVisible(find.byKey(const ValueKey('role_card_merchant')));
    await tester.tap(find.byKey(const ValueKey('role_card_merchant')));
    await tester.pumpAndSettle();

    // Tap Admin card
    await tester.ensureVisible(find.byKey(const ValueKey('role_card_admin')));
    await tester.tap(find.byKey(const ValueKey('role_card_admin')));
    await tester.pumpAndSettle();

    // Tap Customer card
    await tester.ensureVisible(find.byKey(const ValueKey('role_card_customer')));
    await tester.tap(find.byKey(const ValueKey('role_card_customer')));
    await tester.pumpAndSettle();
  });

  testWidgets('ProfileScreen enforces RBAC: hides Merchant Workspace in customer mode', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) {
          final notifier = AuthNotifier();
          notifier.state = const AuthState(
            user: dummyUser,
            accessToken: 'token-abc',
            activeRole: 'customer',
          );
          return notifier;
        }),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Active Mode is CUSTOMER
    expect(find.text('CUSTOMER'), findsOneWidget);
    // Switch Portal / Experience tile should exist
    expect(find.text('Switch Portal / Experience'), findsOneWidget);
    // Merchant Workspace should NOT be present in customer mode
    expect(find.text('Merchant Workspace'), findsNothing);
  });

  testWidgets('ProfileScreen shows Merchant Workspace when activeRole is merchant', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) {
          final notifier = AuthNotifier();
          notifier.state = const AuthState(
            user: dummyUser,
            accessToken: 'token-abc',
            activeRole: 'merchant',
          );
          return notifier;
        }),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Active Mode is MERCHANT
    expect(find.text('MERCHANT'), findsOneWidget);
    // Merchant Workspace should now be visible
    expect(find.text('Merchant Workspace'), findsOneWidget);
  });
}
