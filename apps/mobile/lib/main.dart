import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/constants/app_constants.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/screens/explore_screen.dart';
import 'package:grepmind_mobile/core/screens/saved_screen.dart';
import 'package:grepmind_mobile/core/screens/profile_screen.dart';
import 'package:grepmind_mobile/core/screens/onboarding_screen.dart';
import 'package:grepmind_mobile/core/screens/splash_screen.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/screens/admin_portal_screen.dart';
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
                      : const MainNavigator())
              : const OnboardingScreen(),
    );
  }
}

class MainNavigator extends ConsumerStatefulWidget {
  const MainNavigator({super.key});

  @override
  ConsumerState<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends ConsumerState<MainNavigator> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final activeRole = authState.activeRole ?? 'customer';

    if (activeRole == 'merchant') {
      // Merchant Experience: dedicated workspace & profile
      final merchantScreens = [
        const MerchantWorkspaceScreen(),
        const ProfileScreen(),
      ];
      final maxIndex = merchantScreens.length - 1;
      if (_selectedIndex > maxIndex) {
        _selectedIndex = maxIndex;
      }

      return Scaffold(
        body: IndexedStack(index: _selectedIndex, children: merchantScreens),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_outlined),
              activeIcon: Icon(Icons.storefront),
              label: 'Workspace',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Account',
            ),
          ],
        ),
      );
    }

    // Customer Experience: Explore, Nearby, Saved, Profile
    final customerScreens = [
      const ExploreScreen(),
      _selectedIndex == 1 ? const NearbyMapScreen() : const SizedBox.shrink(),
      const SavedScreen(),
      const ProfileScreen(),
    ];

    // Clamp selectedIndex to valid range
    final maxIndex = customerScreens.length - 1;
    if (_selectedIndex > maxIndex) {
      _selectedIndex = maxIndex;
    }

    final navItems = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), activeIcon: Icon(Icons.explore), label: 'Explore'),
      const BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Nearby'),
      const BottomNavigationBarItem(icon: Icon(Icons.favorite_outline), activeIcon: Icon(Icons.favorite), label: 'Saved'),
      const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: customerScreens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: navItems,
      ),
    );
  }
}
