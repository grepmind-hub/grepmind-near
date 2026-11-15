import 'dart:async';

import 'package:flutter/material.dart';

import 'package:grepmind_mobile/core/constants/app_constants.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/screens/explore_screen.dart';
import 'package:grepmind_mobile/core/screens/home_screen.dart';
import 'package:grepmind_mobile/core/screens/profile_screen.dart';
import 'package:grepmind_mobile/core/screens/onboarding_screen.dart';
import 'package:grepmind_mobile/core/screens/splash_screen.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_platform_orders_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_catalog_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_earnings_screen.dart';
import 'package:grepmind_mobile/core/screens/orders_tab_navigator.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/screens/admin_portal_screen.dart';
import 'package:grepmind_mobile/core/screens/rider_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/rider_earnings_screen.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  // Initialize API client before running the app
  apiClient.init();
  runApp(const ProviderScope(child: GrepmindNearApp()));
}

class GrepmindNearApp extends ConsumerWidget {
  const GrepmindNearApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(context),
      home: authState.isLoading
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
          : const OnboardingScreen(),
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
    final selectedIndex = _selectedIndex.clamp(0, pages.length - 1);
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
          setState(() => _selectedIndex = 0);
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
        bottomNavigationBar: BottomNavigationBar(
          key: const ValueKey('workspace_bottom_navigation'),
          type: BottomNavigationBarType.fixed,
          currentIndex: selectedIndex,
          selectedItemColor: widget.activeRole == 'merchant'
              ? AppTheme.coral
              : (widget.activeRole == 'rider'
                  ? AppTheme.riderAmberDark
                  : AppTheme.emerald),
          onTap: (i) => setState(() {
            _mountedPageIndices.add(i);
            _selectedIndex = i;
          }),
          items: _itemsForRole(widget.activeRole),
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
          _WorkspacePlaceholder(
            title: 'Rider map',
            description:
                'Rider location tracking is not available in this phase.',
            icon: Icons.map_outlined,
          ),
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
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map_rounded),
            label: 'Map',
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
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_rounded),
            activeIcon: Icon(Icons.manage_search_rounded),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Nearby',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ];
    }
  }
}

class _WorkspacePlaceholder extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const _WorkspacePlaceholder({
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mainText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.secondaryText, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
