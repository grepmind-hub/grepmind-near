import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/explore_screen.dart';
import 'package:grepmind_mobile/core/widgets/compact_grocery_card.dart';
import 'package:grepmind_mobile/core/widgets/featured_neighborhood_card.dart';
import 'package:grepmind_mobile/core/widgets/local_business_discovery_card.dart';
import 'package:grepmind_mobile/core/widgets/service_pro_card.dart';

class _TestBusinessesNotifier extends BusinessesNotifier {
  _TestBusinessesNotifier(List<Business> items) {
    state = BusinessesState(items: items);
  }

  @override
  Future<void> search({
    required String query,
    double? lat,
    double? lng,
    int? radiusM,
    String? categorySlug,
    String? city,
    bool? openNow,
    bool? availableNow,
    String sort = 'relevance',
    bool reset = true,
  }) async {
    // Retain initial test state
  }
}

class _TestLocationNotifier extends LocationNotifier {
  _TestLocationNotifier() {
    state = const AppLocation(
      cityName: 'Bhubaneswar',
      localityName: 'Saheed Nagar',
      latitude: 20.2961,
      longitude: 85.8245,
      activeBusinessCount: 14,
    );
  }

  @override
  Future<void> loadDefaultLocation() async {
    // Retain initial test location
  }
}

void main() {
  group('UI Phase 3 — ExploreScreen Redesign', () {
    testWidgets('renders featured neighborhood card, quick grocery items, and business discovery cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      // ignore: avoid_redundant_argument_values
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testBusinessStore = const Business(
        id: 'biz-store-1',
        name: 'Maa Mangala Daily Needs',
        categorySlug: 'grocery',
        categoryName: 'Grocery & Essentials',
        addressText: 'Plot 42, Saheed Nagar',
        locality: 'Saheed Nagar',
        city: 'Bhubaneswar',
        status: 'approved',
        verificationStatus: 'verified',
        rating: 4.8,
        reviewCount: 52,
        isOpenNow: true,
      );

      final testBusinessService = const Business(
        id: 'biz-pro-1',
        name: 'Bijay Electric Works',
        categorySlug: 'electrician',
        categoryName: 'Electrician',
        addressText: 'Shop 12, Nayapalli',
        locality: 'Nayapalli',
        city: 'Bhubaneswar',
        status: 'approved',
        verificationStatus: 'verified',
        rating: 4.9,
        reviewCount: 88,
        isOpenNow: true,
      );

      final container = ProviderContainer(
        overrides: [
          businessesProvider.overrideWith(
            (ref) => _TestBusinessesNotifier([testBusinessStore, testBusinessService]),
          ),
          appLocationProvider.overrideWith(
            (ref) => _TestLocationNotifier(),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ExploreScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Featured Neighborhood Spotlight
      expect(find.byType(FeaturedNeighborhoodCard), findsOneWidget);
      expect(find.text('Fresh Winter Harvest & Specials'), findsOneWidget);

      // Quick Grocery Essentials
      expect(find.text('Fresh Groceries (15–30 mins)'), findsOneWidget);
      expect(find.byType(CompactGroceryCard), findsNWidgets(3));
      expect(find.text('Fresh Red Tomatoes'), findsOneWidget);
      expect(find.text('Kalinga Cold-Pressed Mustard Oil'), findsOneWidget);

      // Reusable Discovery Cards in results list
      expect(find.byType(LocalBusinessDiscoveryCard), findsOneWidget);
      expect(find.text('Maa Mangala Daily Needs'), findsOneWidget);

      expect(find.byType(ServiceProCard), findsOneWidget);
      expect(find.text('Bijay Electric Works'), findsOneWidget);
      expect(find.text('Book Service'), findsOneWidget);
    });

    testWidgets('sticky quick-filter pills dynamically filter business listings', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testBusinessStore = const Business(
        id: 'biz-store-1',
        name: 'Maa Mangala Daily Needs',
        categorySlug: 'grocery',
        categoryName: 'Grocery & Essentials',
        addressText: 'Plot 42, Saheed Nagar',
        locality: 'Saheed Nagar',
        city: 'Bhubaneswar',
        status: 'approved',
        verificationStatus: 'verified',
        rating: 4.8,
        reviewCount: 52,
        isOpenNow: true,
      );

      final testBusinessService = const Business(
        id: 'biz-pro-1',
        name: 'Bijay Electric Works',
        categorySlug: 'electrician',
        categoryName: 'Electrician',
        addressText: 'Shop 12, Nayapalli',
        locality: 'Nayapalli',
        city: 'Bhubaneswar',
        status: 'approved',
        verificationStatus: 'verified',
        rating: 4.9,
        reviewCount: 88,
        isOpenNow: true,
      );

      final container = ProviderContainer(
        overrides: [
          businessesProvider.overrideWith(
            (ref) => _TestBusinessesNotifier([testBusinessStore, testBusinessService]),
          ),
          appLocationProvider.overrideWith(
            (ref) => _TestLocationNotifier(),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ExploreScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially both cards appear under 'All'
      expect(find.byType(LocalBusinessDiscoveryCard), findsOneWidget);
      expect(find.byType(ServiceProCard), findsOneWidget);

      // Tap Services pill
      final servicesPill = find.byKey(const Key('filter_pill_services'));
      expect(servicesPill, findsOneWidget);
      await tester.tap(servicesPill);
      await tester.pumpAndSettle();

      // Only service card is visible
      expect(find.byType(ServiceProCard), findsOneWidget);
      expect(find.byType(LocalBusinessDiscoveryCard), findsNothing);

      // Tap Grocery pill
      final groceryPill = find.byKey(const Key('filter_pill_grocery'));
      expect(groceryPill, findsOneWidget);
      await tester.tap(groceryPill);
      await tester.pumpAndSettle();

      // Only grocery card is visible
      expect(find.byType(LocalBusinessDiscoveryCard), findsOneWidget);
      expect(find.byType(ServiceProCard), findsNothing);

      // Tap All pill
      final allPill = find.byKey(const Key('filter_pill_all'));
      expect(allPill, findsOneWidget);
      await tester.tap(allPill);
      await tester.pumpAndSettle();

      // Both returned
      expect(find.byType(LocalBusinessDiscoveryCard), findsOneWidget);
      expect(find.byType(ServiceProCard), findsOneWidget);
    });
  });
}
