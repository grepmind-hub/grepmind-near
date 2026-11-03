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
    'Home presents its live-offer empty state without fabricating content',
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
      await tester.scrollUntilVisible(
        find.text('Open now'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Services near you'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Recently added'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recently added'), findsOneWidget);
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
}
