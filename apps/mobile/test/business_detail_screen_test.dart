import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/models/business.dart';

class FixtureBusinessDetailNotifier extends BusinessDetailNotifier {
  final BusinessDetail fixtureBusiness;
  FixtureBusinessDetailNotifier(this.fixtureBusiness);

  @override
  Future<void> load(String id) async {
    state = BusinessDetailState(
      detail: fixtureBusiness,
      isLoading: false,
      products: const [],
      services: const [],
      offers: const [],
    );
  }
}

void main() {
  testWidgets('Screen 11: BusinessDetailScreen renders hero, nature badge, tabs, and interactive reviews', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const testBiz = BusinessDetail(
      id: 'biz-auto-1',
      name: 'Chhatia Auto-Rickshaw Stand Association',
      categorySlug: 'cab-auto',
      categoryName: 'Cab & Auto',
      addressText: 'Chhatia, Jajpur',
      locality: 'Chhatia',
      city: 'Jajpur',
      status: 'approved',
      verificationStatus: 'verified',
      distanceM: 200,
      rating: 4.8,
      reviewCount: 190,
      latitude: 20.6120,
      longitude: 86.0465,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessDetailProvider.overrideWith(
            (ref) => FixtureBusinessDetailNotifier(testBiz),
          ),
          favoritesProvider.overrideWith((ref) => FavoritesNotifier()),
        ],
        child: const MaterialApp(
          home: BusinessDetailScreen(businessId: 'biz-auto-1'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 1. Verify business header and nature badge
    expect(find.text('Chhatia Auto-Rickshaw Stand Association'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('TRANSPORT'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);

    // 2. Verify tabs (for Cab & Auto, tab 2 is 'Rides & Fares')
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Rides & Fares'), findsOneWidget);
    expect(find.text('Offers'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);

    // Verify bottom bar has "Book Ride" instead of "Shop Now"
    expect(find.byKey(const ValueKey('book_ride_button')), findsOneWidget);
    expect(find.text('Book Ride'), findsOneWidget);

    // Tap "Book Ride" to verify the ride booking modal opens
    await tester.tap(find.byKey(const ValueKey('book_ride_button')));
    await tester.pumpAndSettle();
    expect(find.text('Book Ride · Cab & Auto'), findsOneWidget);
    expect(find.text('Call Stand / Driver Directly'), findsOneWidget);
    expect(find.text('Schedule Pickup / Request Cab'), findsOneWidget);

    // Close the ride modal by tapping the close icon
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // 3. Switch to Reviews tab
    await tester.tap(find.text('Reviews'));
    await tester.pumpAndSettle();

    // Verify rating summary & "Give Review" button
    expect(find.text('4.8'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('give_review_button')), findsOneWidget);
    expect(find.textContaining('Give Review'), findsOneWidget);

    // 4. Tap "Give Review" to open modal
    final giveReviewBtn = find.byKey(const ValueKey('give_review_button'));
    await tester.ensureVisible(giveReviewBtn);
    await tester.pumpAndSettle();
    await tester.tap(giveReviewBtn);
    await tester.pumpAndSettle();

    expect(find.text('Write a Review'), findsOneWidget);
    expect(find.byKey(const ValueKey('review_star_5')), findsOneWidget);
    expect(find.byKey(const ValueKey('review_comment_input')), findsOneWidget);

    // 5. Fill and submit review
    final commentField = find.byKey(const ValueKey('review_comment_input'));
    await tester.ensureVisible(commentField);
    await tester.enterText(
      commentField,
      'Super quick auto service, arrived in 5 mins near Chhatia temple!',
    );
    await tester.pumpAndSettle();

    final submitBtn = find.byKey(const ValueKey('submit_review_button'));
    await tester.ensureVisible(submitBtn);
    await tester.pumpAndSettle();
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    // 6. Verify review appears in list
    final reviewFinder = find.text(
      'Super quick auto service, arrived in 5 mins near Chhatia temple!',
    );
    await tester.scrollUntilVisible(
      reviewFinder,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(reviewFinder, findsOneWidget);
    expect(find.text('Just now'), findsOneWidget);
  });
}
