import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/utils/category_sample_image.dart';

class FixtureCategories extends CategoriesNotifier {
  @override
  Future<void> load() async {
    state = const CategoriesState(
      items: [
        Category(slug: 'electrician', name: 'Electrician'),
        Category(slug: 'hardware', name: 'Hardware'),
      ],
    );
  }
}

class CapturingBusinessesNotifier extends BusinessesNotifier {
  double? requestedLat;
  double? requestedLng;
  String? requestedCity;
  String? requestedCategorySlug;
  int? requestedRadiusM;

  @override
  Future<void> nearby({
    required double lat,
    required double lng,
    int radiusM = 5000,
    String? city,
    String? categorySlug,
    bool reset = true,
  }) async {
    requestedLat = lat;
    requestedLng = lng;
    requestedCity = city;
    requestedCategorySlug = categorySlug;
    requestedRadiusM = radiusM;
    state = const BusinessesState(
      items: [
        Business(
          id: 'hardware-1',
          name: 'Cuttack Hardware',
          categorySlug: 'hardware',
          categoryName: 'Hardware',
          addressText: 'Badambadi, Cuttack',
          locality: 'Badambadi',
          city: 'Cuttack',
          status: 'approved',
          verificationStatus: 'verified',
          distanceM: 600,
          latitude: 20.466,
          longitude: 85.88,
        ),
        Business(
          id: 'grocery-1',
          name: 'Cuttack Grocery',
          categorySlug: 'grocery',
          categoryName: 'Grocery',
          addressText: 'Badambadi, Cuttack',
          locality: 'Badambadi',
          city: 'Cuttack',
          status: 'approved',
          verificationStatus: 'verified',
          distanceM: 900,
          latitude: 20.467,
          longitude: 85.881,
        ),
      ],
    );
  }
}

void main() {
  testWidgets('initial nearby search uses the selected city center', (
    WidgetTester tester,
  ) async {
    final businesses = CapturingBusinessesNotifier();
    final location = LocationNotifier()
      ..setLocation(
        const AppLocation(
          cityName: 'Cuttack',
          latitude: 20.46575,
          longitude: 85.879,
        ),
      );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocationProvider.overrideWith((ref) => location),
          mapBusinessesProvider.overrideWith((ref) => businesses),
          categoriesProvider.overrideWith((ref) => FixtureCategories()),
        ],
        child: const MaterialApp(home: NearbyMapScreen(initialRadarView: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(businesses.requestedCity, 'Cuttack');
    expect(businesses.requestedLat, 20.46575);
    expect(businesses.requestedLng, 85.879);
    expect(find.text('Cuttack · 5 km radius'), findsOneWidget);
    expect(businesses.requestedRadiusM, 5000);

    await tester.tap(find.byKey(const ValueKey('nearby_radius_selector')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('10 km'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(businesses.requestedRadiusM, 10000);

    await tester.tap(find.byKey(const ValueKey('map_category_hardware')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(businesses.requestedCategorySlug, 'hardware');

    await tester.tap(find.byKey(const ValueKey('map_category_all')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(businesses.requestedCategorySlug, isNull);
    await tester.tap(find.byKey(const ValueKey('nearby_list_view_toggle')));
    await tester.pump();
    expect(find.text('Cuttack Hardware'), findsOneWidget);
    expect(find.text('Cuttack Grocery'), findsOneWidget);
    expect(find.byType(CategorySampleImage), findsNWidgets(2));
  });

  testWidgets(
    'NearbyMapScreen renders top category chips, radar view, and actions',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoriesProvider.overrideWith((ref) => FixtureCategories()),
          ],
          child: const MaterialApp(home: NearbyMapScreen()),
        ),
      );

      // Use bounded pumps since radar animation repeats continuously
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify title and location subtitle
      expect(find.text('Nearby Map'), findsOneWidget);
      expect(find.text(' (5 km radius)'), findsNothing);
      expect(find.text(' · 5 km radius'), findsOneWidget);

      // Verify top category chips
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Electrician'), findsOneWidget);
      expect(find.text('Hardware'), findsOneWidget);

      // Tap Electrician chip
      await tester.tap(find.text('Electrician'));
      await tester.pump(const Duration(milliseconds: 300));

      // Toggle radar view button in AppBar
      final toggleButton = find.byTooltip('Show Radar View');
      if (toggleButton.evaluate().isNotEmpty) {
        await tester.tap(toggleButton);
        await tester.pump(const Duration(milliseconds: 300));
      }
    },
  );
}
