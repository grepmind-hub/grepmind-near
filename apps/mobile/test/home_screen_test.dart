import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/home_feed_provider.dart';
import 'package:grepmind_mobile/core/screens/home_screen.dart';

class _QuietCategoriesNotifier extends CategoriesNotifier {
  @override
  Future<void> load() async {}
}

void main() {
  testWidgets(
    'Home presents live empty states and keeps recent businesses off Home',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeFeedProvider('').overrideWith((ref) async => const HomeFeed()),
            categoriesProvider.overrideWith(
              (ref) => _QuietCategoriesNotifier(),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your neighborhood,\ndiscovered.'), findsOneWidget);
      expect(find.text('Live offers'), findsOneWidget);
      expect(find.text('No live offers right now'), findsOneWidget);
      expect(find.text('Newly approved businesses'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('New near you'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('New near you'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Open now'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Services near you'), findsOneWidget);
    },
  );

  testWidgets('Home renders an offer returned by the city feed', (
    tester,
  ) async {
    const offer = HomeOffer(
      id: 'offer-test-1',
      businessId: 'business-test-1',
      title: 'Offer title from API',
      businessName: 'Merchant name from API',
      city: 'Cuttack',
      discountPercent: 10,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeFeedProvider('')
              .overrideWith((ref) async => const HomeFeed(offers: [offer])),
          categoriesProvider.overrideWith((ref) => _QuietCategoriesNotifier()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offer title from API'), findsOneWidget);
    expect(find.text('Merchant name from API · Cuttack'), findsOneWidget);
    expect(find.text('10% OFF'), findsOneWidget);
  });

  testWidgets('Home renders a real catalog arrival returned by the feed', (
    tester,
  ) async {
    final item = HomeCatalogItem(
      id: 'catalog-item-1',
      type: 'product',
      businessId: 'business-item-1',
      businessName: 'Local market from API',
      city: 'Cuttack',
      categoryName: 'Grocery',
      name: 'Fresh rice from API',
      currency: 'INR',
      publishedAt: DateTime.utc(2026, 11, 4),
      price: 75,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeFeedProvider('')
              .overrideWith((ref) async => HomeFeed(newArrivals: [item])),
          categoriesProvider.overrideWith((ref) => _QuietCategoriesNotifier()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Fresh rice from API'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Fresh rice from API'), findsOneWidget);
    expect(find.textContaining('Local market from API'), findsOneWidget);
    expect(find.text('₹75'), findsOneWidget);
  });
}
