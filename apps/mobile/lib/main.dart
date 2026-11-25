import 'dart:async';

import 'package:flutter/material.dart';

import 'package:grepmind_mobile/core/constants/app_constants.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/screens/explore_screen.dart';
import 'package:grepmind_mobile/core/screens/home_screen.dart';
import 'package:grepmind_mobile/core/screens/profile_screen.dart';
import 'package:grepmind_mobile/features/onboarding/introduction_screen.dart';
import 'package:grepmind_mobile/core/screens/splash_screen.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_platform_orders_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_catalog_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_earnings_screen.dart';
import 'package:grepmind_mobile/core/screens/orders_tab_navigator.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/screens/admin_portal_screen.dart';
import 'package:grepmind_mobile/core/screens/rider_earnings_screen.dart';
import 'package:grepmind_mobile/core/screens/rider_locality_hubs_screen.dart';
import 'package:grepmind_mobile/core/screens/rider_workspace_screen.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/notifications/firebase_bootstrap.dart';
import 'package:grepmind_mobile/core/notifications/notification_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseConfig = FirebaseBuildConfig.fromEnvironment();
  unawaited(() async {
    if (firebaseConfig.isEmpty) {
      await initializeFirebaseFromNative();
    } else {
      await initializeFirebase(firebaseConfig);
    }
    // NotificationManager is initialized after the first frame
    // to ensure an Activity context is available for permission requests.
  }());
  // Initialize API client before running the app
  apiClient.init();
  runApp(const ProviderScope(child: GrepmindNearApp()));
}

class GrepmindNearApp extends ConsumerStatefulWidget {
  const GrepmindNearApp({super.key});

  @override
  ConsumerState<GrepmindNearApp> createState() => _GrepmindNearAppState();
}

class _GrepmindNearAppState extends ConsumerState<GrepmindNearApp> {
  bool _splashComplete = false;
  bool _testFastTransition = false;

  @override
  void initState() {
    super.initState();
    // Request notification permission after the first frame is rendered,
    // ensuring an Activity context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final manager = NotificationManager();
      await manager.initialize();
    } catch (_) {
      // Initialization failure must not block app startup.
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    if (authState.isLoading) {
      _testFastTransition = true;
    }

    final shouldShowImmediate =
        _testFastTransition &&
        !authState.isLoading &&
        authState.isAuthenticated;

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(context),
      home: (!_splashComplete && !shouldShowImmediate)
          ? SplashScreen(
              onComplete: () {
                if (mounted) setState(() => _splashComplete = true);
              },
            )
          : authState.isLoading
          ? const SplashScreen()
          : authState.isAuthenticated
          ? (authState.activeRole == null
                ? const RoleSelectionScreen()
                : authState.activeRole == 'admin'
                ? const AdminPortalScreen()
                : MainNavigator(
                    key: ValueKey('workspace-${authState.activeRole}'),
                    activeRole: authState.activeRole ?? 'customer',
                  ))
          : const IntroductionScreen(),
    );
  }
}

class MainNavigator extends ConsumerStatefulWidget {
  final String activeRole;

  const MainNavigator({super.key, required this.activeRole});

  @override
  ConsumerState<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends ConsumerState<MainNavigator> {
  int _selectedIndex = 0;
  bool _handlingNestedBack = false;
  Timer? _backGuardTimer;
  final Set<int> _mountedPageIndices = {0};
  final GlobalKey<NavigatorState> _ordersNavigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void didUpdateWidget(covariant MainNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeRole != widget.activeRole) {
      _selectedIndex = 0;
      _backGuardTimer?.cancel();
      _handlingNestedBack = false;
      _mountedPageIndices
        ..clear()
        ..add(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pagesForRole(widget.activeRole);
    final selectedIndex = widget.activeRole == 'customer'
        ? ref.watch(customerTabIndexProvider).clamp(0, pages.length - 1)
        : _selectedIndex.clamp(0, pages.length - 1);
    _mountedPageIndices.add(selectedIndex);
    return PopScope<Object?>(
      canPop: selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || selectedIndex == 0 || _handlingNestedBack) return;
        final ordersNavigator = _ordersNavigatorKey.currentState;
        if (selectedIndex == 3 && (ordersNavigator?.canPop() ?? false)) {
          _handlingNestedBack = true;
          ordersNavigator?.pop();
          _backGuardTimer?.cancel();
          _backGuardTimer = Timer(const Duration(milliseconds: 300), () {
            _handlingNestedBack = false;
          });
        } else {
          if (widget.activeRole == 'customer') {
            ref.read(customerTabIndexProvider.notifier).state = 0;
          } else {
            setState(() => _selectedIndex = 0);
          }
        }
      },
      child: Scaffold(
        key: const ValueKey('workspace_scaffold'),
        body: IndexedStack(
          index: selectedIndex,
          children: [
            for (var index = 0; index < pages.length; index++)
              _mountedPageIndices.contains(index)
                  ? TickerMode(
                      enabled: index == selectedIndex,
                      child: pages[index],
                    )
                  : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              color: AbashyakaColors.pureWhite,
              borderRadius: BorderRadius.circular(28),
              boxShadow: AbashyakaShadows.floatingNav,
              border: Border.all(
                color: AbashyakaColors.silverGlass,
                width: 1.2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BottomNavigationBar(
                key: const ValueKey('workspace_bottom_navigation'),
                type: BottomNavigationBarType.fixed,
                backgroundColor: AbashyakaColors.pureWhite,
                elevation: 0,
                currentIndex: selectedIndex,
                selectedItemColor: widget.activeRole == 'merchant'
                    ? AbashyakaColors.metallicTealDark
                    : (widget.activeRole == 'rider'
                          ? AppTheme.riderAmberDark
                          : AbashyakaColors.metallicTealDark),
                unselectedItemColor: AbashyakaColors.secondaryText,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
                onTap: (i) {
                  _mountedPageIndices.add(i);
                  if (widget.activeRole == 'customer') {
                    ref.read(customerTabIndexProvider.notifier).state = i;
                  } else {
                    setState(() => _selectedIndex = i);
                  }
                },
                items: _itemsForRole(widget.activeRole),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _backGuardTimer?.cancel();
    super.dispose();
  }

  List<Widget> _pagesForRole(String role) {
    switch (role) {
      case 'merchant':
        return const [
          MerchantWorkspaceScreen(),
          MerchantPlatformOrdersScreen(),
          MerchantCatalogScreen(),
          MerchantEarningsScreen(),
          ProfileScreen(),
        ];
      case 'rider':
        return const [
          RiderDashboardScreen(),
          RiderDeliveriesScreen(),
          RiderLocalityHubsScreen(),
          RiderEarningsScreen(),
          RiderWorkspaceProfileScreen(),
        ];
      default:
        return [
          const HomeScreen(),
          const ExploreScreen(),
          const NearbyMapScreen(),
          OrdersTabNavigator(navigatorKey: _ordersNavigatorKey),
          const ProfileScreen(),
        ];
    }
  }

  List<BottomNavigationBarItem> _itemsForRole(String role) {
    switch (role) {
      case 'merchant':
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2_rounded),
            label: 'Catalog',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Earnings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ];
      case 'rider':
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.delivery_dining_outlined),
            activeIcon: Icon(Icons.delivery_dining_rounded),
            label: 'Deliveries',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.hub_outlined),
            activeIcon: Icon(Icons.hub_rounded),
            label: 'Hubs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Earnings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ];
      default:
        return [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4EA),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.home_rounded, color: Color(0xFF0B6B4A)),
            ),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.location_on_outlined),
            activeIcon: Icon(Icons.location_on),
            label: 'Nearby',
          ),
          const BottomNavigationBarItem(
            icon: Badge(
              backgroundColor: Color(0xFFFF8A00),
              label: Text(
                '1',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Icon(Icons.inventory_2_outlined),
            ),
            activeIcon: Badge(
              backgroundColor: Color(0xFFFF8A00),
              label: Text(
                '1',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Icon(Icons.inventory_2),
            ),
            label: 'Orders',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ];
    }
  }
}
