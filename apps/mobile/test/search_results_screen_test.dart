import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/data/category_listings_data.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/search_results_screen.dart';

class _MockBusinessesNotifier extends BusinessesNotifier {
  _MockBusinessesNotifier(List<Business> items) {
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
    final filtered = CategoryListingsData.getListingsForCategory(
      categorySlug,
      query: query,
      maxRadiusM: radiusM,
      sortBy: sort,
    );
    state = BusinessesState(items: filtered);
  }
}

void main() {
  group('Screen 9: Search & Filter Results UI Tests', () {
    testWidgets('renders search header, map action, and filter chips with Premium UI tokens', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testBusinesses = CategoryListingsData.allListings;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessesProvider.overrideWith(
              (ref) => _MockBusinessesNotifier(testBusinesses),
            ),
          ],
          child: const MaterialApp(
            home: SearchResultsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check search input field
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search food, shops, services, doctors...'), findsOneWidget);

      // Check map view action button
      expect(find.byIcon(Icons.map_outlined), findsOneWidget);

      // Check filter chips
      expect(find.text('5 km'), findsOneWidget);
      expect(find.text('Nearest'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Open Now'), findsOneWidget);

      // Check quick categories row exists when no category is active
      expect(find.text('Food'), findsWidgets);
      expect(find.text('Grocery'), findsWidgets);
      expect(find.text('Medicines'), findsWidgets);
      expect(find.text('Doctors'), findsWidgets);
      expect(find.text('Services'), findsWidgets);
    });

    testWidgets('radius bottom sheet opens and displays radius options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessesProvider.overrideWith(
              (ref) => _MockBusinessesNotifier(CategoryListingsData.allListings),
            ),
          ],
          child: const MaterialApp(
            home: SearchResultsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on radius chip
      await tester.tap(find.text('5 km'));
      await tester.pumpAndSettle();

      // Check radius bottom sheet
      expect(find.text('Search Radius'), findsOneWidget);
      expect(find.text('Within 1 km'), findsOneWidget);
      expect(find.text('Within 2 km'), findsOneWidget);
      expect(find.text('Within 5 km'), findsOneWidget);
      expect(find.text('Within 10 km'), findsOneWidget);
      expect(find.text('Within 20 km'), findsOneWidget);

      // Tap 10 km
      await tester.tap(find.text('Within 10 km'));
      await tester.pumpAndSettle();

      // Verify sheet dismissed and chip updated
      expect(find.text('Search Radius'), findsNothing);
      expect(find.text('10 km'), findsOneWidget);
    });

    testWidgets('sort bottom sheet opens and displays sort options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessesProvider.overrideWith(
              (ref) => _MockBusinessesNotifier(CategoryListingsData.allListings),
            ),
          ],
          child: const MaterialApp(
            home: SearchResultsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on sort chip
      await tester.tap(find.text('Nearest'));
      await tester.pumpAndSettle();

      // Check sort options
      expect(find.text('Sort Results By'), findsOneWidget);
      expect(find.text('Nearest First (Distance)'), findsOneWidget);
      expect(find.text('Best Match (Relevance)'), findsOneWidget);
      expect(find.text('Highest Rated (Reviews)'), findsOneWidget);

      // Tap Top Rated
      await tester.tap(find.text('Highest Rated (Reviews)'));
      await tester.pumpAndSettle();

      // Verify sheet dismissed and chip updated
      expect(find.text('Sort Results By'), findsNothing);
      expect(find.text('Top Rated'), findsOneWidget);
    });

    testWidgets('empty state displays approved service places and zero raw pincodes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessesProvider.overrideWith(
              (ref) => _MockBusinessesNotifier(const []),
            ),
          ],
          child: const MaterialApp(
            home: SearchResultsScreen(initialQuery: 'NonExistentQueryXYZ'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify empty state
      expect(find.text('No businesses found'), findsOneWidget);
      expect(
        find.text('Try expanding your radius, searching nearby hubs like Chhatia, Kuanpal, Jagatpur, Tangi, or Chandikhol, or clearing filters.'),
        findsOneWidget,
      );
      expect(find.text('Reset Filters & Show All'), findsOneWidget);

      // Verify zero raw pincodes displayed
      expect(find.textContaining('754023'), findsNothing);
      expect(find.textContaining('754024'), findsNothing);
    });
  });
}
