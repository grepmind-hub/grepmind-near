import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/widgets/compact_grocery_card.dart';
import 'package:grepmind_mobile/core/widgets/featured_neighborhood_card.dart';
import 'package:grepmind_mobile/core/widgets/food_item_card.dart';
import 'package:grepmind_mobile/core/widgets/local_business_discovery_card.dart';
import 'package:grepmind_mobile/core/widgets/service_pro_card.dart';

void main() {
  group('UI Phase 1 — Premium Cards Suite', () {
    testWidgets(
      'CompactGroceryCard renders product info, handles add & stepper callbacks',
      (tester) async {
        int addCalled = 0;
        int incCalled = 0;
        int decCalled = 0;

        // Test 1: In-cart quantity is 0 -> Displays ADD button
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 180,
                height: 250,
                child: CompactGroceryCard(
                  name: 'Fresh Red Tomatoes',
                  unit: '1 kg',
                  priceMinor: 4200,
                  mrpMinor: 5000,
                  badgeText: '16% OFF',
                  onAdd: () => addCalled++,
                ),
              ),
            ),
          ),
        );

        expect(find.text('Fresh Red Tomatoes'), findsOneWidget);
        expect(find.text('1 kg'), findsOneWidget);
        expect(find.text('₹42'), findsOneWidget);
        expect(find.text('16% OFF'), findsOneWidget);
        expect(find.text('ADD'), findsOneWidget);

        await tester.tap(find.text('ADD'));
        expect(addCalled, 1);

        // Test 2: In-cart quantity > 0 -> Displays stepper
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 180,
                height: 250,
                child: CompactGroceryCard(
                  name: 'Fresh Red Tomatoes',
                  unit: '1 kg',
                  priceMinor: 4200,
                  quantityInCart: 2,
                  onIncrement: () => incCalled++,
                  onDecrement: () => decCalled++,
                ),
              ),
            ),
          ),
        );

        expect(find.text('2'), findsOneWidget);
        expect(find.byIcon(Icons.remove), findsOneWidget);
        expect(find.byIcon(Icons.add), findsOneWidget);

        await tester.tap(find.byIcon(Icons.add));
        expect(incCalled, 1);

        await tester.tap(find.byIcon(Icons.remove));
        expect(decCalled, 1);
      },
    );

    testWidgets(
      'FoodItemCard renders veg indicator, bestseller badge, and stepper',
      (tester) async {
        int incCalled = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodItemCard(
                name: 'Paneer Butter Masala',
                priceMinor: 24000,
                description:
                    'Rich tomato cashew gravy with fresh cottage cheese',
                isBestseller: true,
                isCustomizable: true,
                quantityInCart: 1,
                onIncrement: () => incCalled++,
              ),
            ),
          ),
        );

        expect(find.text('Paneer Butter Masala'), findsOneWidget);
        expect(find.text('₹240'), findsOneWidget);
        expect(find.text('★ BESTSELLER'), findsOneWidget);
        expect(find.text('customisable'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.add));
        expect(incCalled, 1);
      },
    );

    testWidgets(
      'LocalBusinessDiscoveryCard renders storefront details and actions',
      (tester) async {
        bool tapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LocalBusinessDiscoveryCard(
                name: 'Maa Tarini Hardware & Paints',
                category: 'Hardware',
                rating: 4.8,
                reviewCount: 96,
                distanceKm: 1.4,
                locality: 'Saheed Nagar, Bhubaneswar',
                onPrimaryAction: () => tapped = true,
              ),
            ),
          ),
        );

        expect(find.text('Maa Tarini Hardware & Paints'), findsOneWidget);
        expect(find.text('Hardware'), findsOneWidget);
        expect(find.text('Verified'), findsOneWidget);
        expect(find.text('4.8'), findsOneWidget);
        expect(find.text(' (96)'), findsOneWidget);
        expect(find.text('1.4 km'), findsOneWidget);
        expect(find.text('View Store'), findsOneWidget);

        await tester.tap(find.text('View Store'));
        expect(tapped, isTrue);
      },
    );

    testWidgets(
      'ServiceProCard renders verified pro details and booking action',
      (tester) async {
        bool booked = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ServiceProCard(
                name: 'Ramesh Mohanty',
                specialization: 'Licensed Electrician',
                experienceYears: 9,
                rating: 4.9,
                jobsCompleted: 142,
                startingPriceMinor: 14900,
                onBook: () => booked = true,
              ),
            ),
          ),
        );

        expect(find.text('Ramesh Mohanty'), findsOneWidget);
        expect(find.text('Licensed Electrician'), findsOneWidget);
        expect(find.text('9+ yrs exp'), findsOneWidget);
        expect(find.text('4.9'), findsOneWidget);
        expect(find.text(' (142 jobs)'), findsOneWidget);
        expect(find.text('Starts at ₹149'), findsOneWidget);
        expect(find.text('Book Service'), findsOneWidget);

        await tester.tap(find.text('Book Service'));
        expect(booked, isTrue);
      },
    );

    testWidgets(
      'FeaturedNeighborhoodCard renders editorial tag, title, and cta',
      (tester) async {
        bool tapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FeaturedNeighborhoodCard(
                title: 'Fresh Winter Greens from Pipili',
                subtitle: 'Hand-picked daily from local farming cooperatives',
                onTap: () => tapped = true,
              ),
            ),
          ),
        );

        expect(find.text('LOCAL HARVEST'), findsOneWidget);
        expect(find.text('Fresh Winter Greens from Pipili'), findsOneWidget);
        expect(find.text('Explore Collection'), findsOneWidget);

        await tester.tap(find.text('Explore Collection'));
        expect(tapped, isTrue);
      },
    );
  });
}
