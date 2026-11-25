import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/saved_screen.dart';

class FixtureFavoritesNotifier extends FavoritesNotifier {
  FixtureFavoritesNotifier(List<Business> initialItems) {
    state = FavoritesState(items: initialItems);
  }

  @override
  Future<void> load() async {}

  @override
  Future<bool?> toggle(String businessId) async {
    final items = [...state.items];
    final index = items.indexWhere((business) => business.id == businessId);
    if (index >= 0) {
      items.removeAt(index);
      state = state.copyWith(items: items);
      return false;
    }
    return true;
  }

  @override
  Future<bool> clearAll() async {
    state = const FavoritesState();
    return true;
  }
}

const _businessCab = Business(
  id: 'biz_cab_chhatia',
  name: 'Maa Tarini Auto Stand Chhatia',
  categorySlug: 'cab_auto',
  categoryName: 'Cab & Auto',
  addressText: 'Near Chhatia Temple Gate',
  locality: 'Chhatia',
  city: 'Jajpur',
  distanceM: 200,
  status: 'active',
  verificationStatus: 'verified',
  rating: 4.8,
  reviewCount: 42,
  isOpenNow: true,
);

const _businessDoctor = Business(
  id: 'biz_doc_kuanpal',
  name: 'Dr. S. K. Nayak Clinic',
  categorySlug: 'doctors',
  categoryName: 'Doctors & Clinics',
  addressText: 'Main Road, Kuanpal Bazar',
  locality: 'Kuanpal',
  city: 'Cuttack',
  distanceM: 500,
  status: 'active',
  verificationStatus: 'verified',
  rating: 4.9,
  reviewCount: 68,
  isOpenNow: true,
);

const _businessGrocery = Business(
  id: 'biz_grocery_tangi',
  name: 'Maa Mangala Super Store',
  categorySlug: 'grocery',
  categoryName: 'Grocery & Staples',
  addressText: 'NH-16 Chowk, Tangi',
  locality: 'Tangi',
  city: 'Cuttack',
  distanceM: 350,
  status: 'active',
  verificationStatus: 'verified',
  rating: 4.7,
  reviewCount: 31,
  isOpenNow: true,
);

void main() {
  testWidgets(
    'Screen 16: SavedScreen renders header, nature badges, and contextual CTAs',
    (tester) async {
      final favorites = FixtureFavoritesNotifier([
        _businessCab,
        _businessDoctor,
        _businessGrocery,
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [favoritesProvider.overrideWith((ref) => favorites)],
          child: const MaterialApp(home: SavedScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify header title & bookmark count
      expect(find.text('Saved Places'), findsOneWidget);
      expect(find.text('3 places bookmarked'), findsOneWidget);

      // 2. Verify filter chips
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Shops & Retail'), findsOneWidget);
      expect(find.text('Cab & Auto'), findsOneWidget);

      // 3. Verify businesses and nature badges
      expect(find.text('Maa Tarini Auto Stand Chhatia'), findsOneWidget);
      expect(find.text('TRANSPORT'), findsOneWidget);
      expect(find.text('Book Ride'), findsOneWidget);

      expect(find.text('Dr. S. K. Nayak Clinic'), findsOneWidget);
      expect(find.text('HEALTHCARE'), findsOneWidget);
      expect(find.text('Book Appointment'), findsOneWidget);

      expect(find.text('Maa Mangala Super Store'), findsOneWidget);
      expect(find.text('GROCERY'), findsOneWidget);
      expect(find.text('Shop Grocery'), findsOneWidget);

      // 4. Test category filter: tap "Cab & Auto" chip
      await tester.tap(find.text('Cab & Auto'));
      await tester.pumpAndSettle();

      expect(find.text('Maa Tarini Auto Stand Chhatia'), findsOneWidget);
      expect(find.text('Dr. S. K. Nayak Clinic'), findsNothing);
      expect(find.text('Maa Mangala Super Store'), findsNothing);

      // Return to all
      await tester.tap(find.text('All (3)'));
      await tester.pumpAndSettle();

      // 5. Remove single item by tapping heart
      final cabHeartFinder = find.byKey(
        const ValueKey('saved_heart_biz_cab_chhatia'),
      );
      expect(cabHeartFinder, findsOneWidget);
      await tester.tap(cabHeartFinder);
      await tester.pumpAndSettle();

      expect(favorites.state.items.length, 2);
      expect(find.text('Maa Tarini Auto Stand Chhatia'), findsNothing);
      expect(
        find.text('Removed "Maa Tarini Auto Stand Chhatia" from saved places'),
        findsOneWidget,
      );

      // 6. Test clear all dialog
      await tester.tap(find.byTooltip('Clear all'));
      await tester.pumpAndSettle();

      expect(find.text('Clear all saved places?'), findsOneWidget);
      await tester.tap(find.text('Clear all').last);
      await tester.pumpAndSettle();

      expect(favorites.state.items, isEmpty);
      expect(find.text('No saved places yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('explore_nearby_button')), findsOneWidget);
    },
  );

  testWidgets(
    'Screen 16: SavedScreen empty state renders explore button & recommendations',
    (tester) async {
      final favorites = FixtureFavoritesNotifier([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [favoritesProvider.overrideWith((ref) => favorites)],
          child: const MaterialApp(home: SavedScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved Places'), findsOneWidget);
      expect(find.text('Chhatia, Kuanpal & nearby'), findsOneWidget);
      expect(find.text('No saved places yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('explore_nearby_button')), findsOneWidget);
      expect(find.text('Popular in Chhatia & Nearby'), findsOneWidget);
    },
  );
}
