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
              ? const MainNavigator()
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
    final isMerchant = authState.user?.roles.contains('merchant') == true ||
        authState.user?.roles.contains('professional') == true;

    final screens = [
      const ExploreScreen(),
      const NearbyMapScreen(),
      const SavedScreen(),
      const ProfileScreen(),
      if (isMerchant) const MerchantWorkspaceScreen(),
    ];

    // Clamp selectedIndex to valid range
    final maxIndex = screens.length - 1;
    if (_selectedIndex > maxIndex) {
      _selectedIndex = maxIndex;
    }

    final navItems = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), activeIcon: Icon(Icons.explore), label: 'Explore'),
      const BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Nearby'),
      const BottomNavigationBarItem(icon: Icon(Icons.favorite_outline), activeIcon: Icon(Icons.favorite), label: 'Saved'),
      const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
      if (isMerchant)
        const BottomNavigationBarItem(
          icon: Icon(Icons.store_outlined),
          activeIcon: Icon(Icons.store),
          label: 'Merchant',
        ),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: navItems,
      ),
    );
  }
}
