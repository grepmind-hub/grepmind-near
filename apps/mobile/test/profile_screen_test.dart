import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/profile_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_registration_screen.dart';

void main() {
  const user = AppUser(
    id: '12345678-1234-5678-9012-123456789012',
    phoneE164: '+919876543210',
    displayName: 'A Grepmind Customer With A Long Name',
    status: 'active',
    preferredLanguage: 'en',
    roles: ['customer'],
  );

  ProviderContainer container() => ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) {
        final notifier = AuthNotifier();
        notifier.state = const AuthState(
          user: user,
          accessToken: 'test-token',
          activeRole: 'customer',
        );
        return notifier;
      }),
    ],
  );

  testWidgets(
    'profile shows compact account ID and actions without password language',
    (tester) async {
      final scope = container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('short_account_id')), findsOneWidget);
      expect(find.text(user.id), findsNothing);
      expect(find.text('Sign-in & security'), findsOneWidget);
      expect(find.text('Change Password'), findsNothing);
      expect(
        find.byKey(const ValueKey('profile_photo_button')),
        findsOneWidget,
      );
      expect(find.text('Notification Settings'), findsOneWidget);
      expect(find.text('Privacy & data'), findsOneWidget);
      scope.dispose();
    },
  );

  testWidgets(
    'security option explains OTP sign-in rather than offering a password change',
    (tester) async {
      final scope = container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign-in & security'));
      await tester.tap(find.text('Sign-in & security'));
      await tester.pumpAndSettle();

      expect(find.text('Secure OTP sign-in'), findsOneWidget);
      expect(
        find.textContaining('This account has no password'),
        findsOneWidget,
      );
      scope.dispose();
    },
  );

  testWidgets('notification settings clearly disclose push delivery status', (
    tester,
  ) async {
    final scope = container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bookings and orders'), findsOneWidget);
    expect(find.text('Service requests'), findsOneWidget);
    expect(find.text('Local offers'), findsOneWidget);
    expect(
      find.textContaining('Mobile push delivery is not enabled yet'),
      findsOneWidget,
    );
    scope.dispose();
  });

  testWidgets('profile photo action offers camera and gallery sources', (
    tester,
  ) async {
    final scope = container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile_photo_button')));
    await tester.pumpAndSettle();

    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    scope.dispose();
  });

  testWidgets('notification settings are reachable from the profile tab', (
    tester,
  ) async {
    final scope = container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Notification Settings'));
    await tester.tap(find.text('Notification Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Notification settings'), findsOneWidget);
    expect(find.text('Bookings and orders'), findsOneWidget);
    scope.dispose();
  });

  testWidgets('merchant onboarding renders complete API taxonomy and search', (
    tester,
  ) async {
    final scope = container();
    final categories = [
      ('grocery', 'Grocery'),
      ('hardware', 'Hardware'),
      ('medical', 'Medical & Pharmacy'),
      ('restaurant', 'Restaurant & Food'),
      ('salon', 'Salon & Beauty'),
      ('plumber', 'Plumber'),
      ('electrician', 'Electrician'),
      ('carpenter', 'Carpenter'),
      ('tailor', 'Tailor'),
      ('general', 'General Store'),
      ('fashion', 'Fashion & Lifestyle'),
      ('electronics', 'Electronics & Mobile'),
      ('home_kitchen', 'Home & Kitchen'),
      ('health_wellness', 'Health & Wellness'),
      ('sports_fitness', 'Sports & Fitness'),
      ('automotive', 'Automotive & Repairs'),
      ('books_stationery', 'Books & Stationery'),
      ('cleaning', 'Cleaning & Pest Control'),
      ('hotel', 'Hotels & Stays'),
    ];
    scope.read(categoriesProvider.notifier).state = CategoriesState(
      items: categories
          .map((item) => Category(slug: item.$1, name: item.$2))
          .toList(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: const MaterialApp(home: MerchantRegistrationScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search all 19 categories'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('merchant_category_hotel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('merchant_category_cleaning')),
      findsOneWidget,
    );
    expect(find.text('FOOD & HOSPITALITY'), findsOneWidget);
    expect(find.text('Hotels & Stays'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('merchant_category_search')),
      'pharmacy',
    );
    await tester.pumpAndSettle();
    expect(find.text('Medical & Pharmacy'), findsOneWidget);
    expect(find.text('Hotels & Stays'), findsNothing);

    scope.dispose();
  });
}
