import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';
import 'package:grepmind_mobile/core/screens/orders_tab_navigator.dart';
import 'package:grepmind_mobile/core/screens/order_shopping_hub_screen.dart';
import 'package:grepmind_mobile/main.dart';

void main() {
  const customer = AppUser(
    id: 'customer-id',
    phoneE164: '+919876543210',
    displayName: 'Test Customer',
    status: 'active',
    preferredLanguage: 'en',
    roles: ['customer'],
  );
  const merchant = AppUser(
    id: 'merchant-id',
    phoneE164: '+919876543211',
    displayName: 'Test Merchant',
    status: 'active',
    preferredLanguage: 'en',
    roles: ['customer', 'merchant'],
  );

  testWidgets('Customer navigation exposes Orders and Saved under Profile', (
    tester,
  ) async {
    final container = _containerWithUser(customer, 'customer');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainNavigator(activeRole: 'customer')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final navigation = find.byKey(
      const ValueKey('workspace_bottom_navigation'),
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Explore')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Nearby')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Orders')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Saved')),
      findsNothing,
    );
    expect(find.byType(NearbyMapScreen), findsNothing);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Orders')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(OrderShoppingHubScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('orders_food_catalog')), findsOneWidget);
    final ordersEntry = find.byKey(const ValueKey('orders_history_entry'));
    await tester.drag(
      find.byKey(const ValueKey('orders_shopping_hub_scroll')),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    expect(ordersEntry, findsOneWidget);
    final myOrders = find.text('My Orders');
    await tester.ensureVisible(myOrders);
    await tester.tap(myOrders);
    await tester.pumpAndSettle();
    expect(find.text('Orders & bookings'), findsOneWidget);
    final nestedOrdersNavigator = find.descendant(
      of: find.byType(OrdersTabNavigator),
      matching: find.byType(Navigator),
    );
    expect(
      tester.state<NavigatorState>(nestedOrdersNavigator).canPop(),
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(OrderShoppingHubScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Browse categories'), findsOneWidget);
    expect(find.byType(NearbyMapScreen), findsNothing);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Nearby')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NearbyMapScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Browse categories'), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Profile')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('My Profile'), findsOneWidget);
    final savedAction = find.byKey(const ValueKey('profile_saved_businesses'));
    await tester.ensureVisible(savedAction);
    expect(savedAction, findsOneWidget);
    expect(tester.widget<InkWell>(savedAction).onTap, isNotNull);
    final savedLabel = find.text('Saved businesses');
    await tester.ensureVisible(savedLabel);
    final savedNavigator = Navigator.of(tester.element(savedAction));
    await tester.tap(savedAction);
    expect(savedNavigator.canPop(), isTrue);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    expect(find.text('Saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('Merchant workspace has the approved five-tab navigation', (
    tester,
  ) async {
    final container = _containerWithUser(merchant, 'merchant');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainNavigator(activeRole: 'merchant')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final navigation = find.byKey(
      const ValueKey('workspace_bottom_navigation'),
    );
    for (final label in [
      'Dashboard',
      'Orders',
      'Catalog',
      'Earnings',
      'Profile',
    ]) {
      expect(
        find.descendant(of: navigation, matching: find.text(label)),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Orders')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Partner Orders'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('Rider operational tabs are clearly marked unavailable', (
    tester,
  ) async {
    const rider = AppUser(
      id: 'rider-id',
      phoneE164: '+919876543212',
      displayName: 'Test Rider',
      status: 'active',
      preferredLanguage: 'en',
      roles: ['customer', 'rider'],
    );
    final container = _containerWithUser(rider, 'rider');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainNavigator(activeRole: 'rider')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final navigation = find.byKey(
      const ValueKey('workspace_bottom_navigation'),
    );
    for (final label in [
      'Dashboard',
      'Deliveries',
      'Hubs',
      'Earnings',
      'Profile',
    ]) {
      expect(
        find.descendant(of: navigation, matching: find.text(label)),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Hubs')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Profile')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rider profile'), findsOneWidget);
    final riderLogout = find.byKey(const ValueKey('rider_logout_button'));
    await tester.ensureVisible(riderLogout);
    expect(riderLogout, findsOneWidget);
    await tester.tap(riderLogout);
    await tester.pumpAndSettle();
    expect(find.text('Are you sure you want to log out?'), findsOneWidget);
    await tester.tap(find.text('LOG OUT'));
    await tester.pumpAndSettle();
    expect(container.read(authProvider).isAuthenticated, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}

ProviderContainer _containerWithUser(AppUser user, String activeRole) {
  return ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) {
        return _TestAuthNotifier(
          AuthState(
            user: user,
            accessToken: 'test-token',
            activeRole: activeRole,
          ),
        );
      }),
    ],
  );
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(AuthState initialState) : super.forTesting() {
    state = initialState;
  }

  @override
  Future<AppUser?> refreshCurrentUser() async => state.user;

  @override
  Future<bool> setActiveRole(String role) async {
    final roles = state.user?.roles ?? const <String>[];
    final permitted = switch (role) {
      'customer' => roles.contains('customer'),
      'merchant' =>
        roles.contains('merchant') || roles.contains('professional'),
      'rider' => roles.contains('rider'),
      'admin' => roles.contains('admin'),
      _ => false,
    };
    if (!permitted) return false;
    state = state.copyWith(activeRole: role);
    return true;
  }

  @override
  Future<void> logout() async {
    state = const AuthState();
  }
}
