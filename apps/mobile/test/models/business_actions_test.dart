import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';

void main() {
  group('Business Action & Service Classification Tests', () {
    test('Service trade categories correctly identified as service providers', () {
      final trades = [
        'electrician',
        'plumber',
        'carpenter',
        'tailor',
        'painter',
        'salon',
        'cleaning',
        'pest-control',
      ];

      for (final trade in trades) {
        final biz = Business(
          id: 'test-$trade',
          name: 'Pro $trade',
          slug: 'pro-$trade',
          categorySlug: trade,
          addressText: 'Market Street, Bhubaneswar',
          status: 'approved',
          verificationStatus: 'verified',
        );

        expect(biz.isServiceProvider, isTrue, reason: '$trade should be a service provider');
        expect(biz.shouldOpenServiceProfile, isTrue, reason: '$trade should open service profile');
        expect(biz.shopActionLabel, 'Book Service', reason: '$trade should display Book Service');
      }
    });

    test('Retail shops do NOT show Book Service and have contextual action labels', () {
      // 1. Grocery with delivery enabled
      const groceryDelivery = Business(
        id: 'g-1',
        name: 'Fresh Mart Grocery',
        slug: 'fresh-mart',
        categorySlug: 'grocery',
        addressText: 'Market Street, Bhubaneswar',
        status: 'approved',
        verificationStatus: 'verified',
        deliveryEnabled: true,
        acceptsRequests: true, // Should NOT cause Book Service
      );
      expect(groceryDelivery.isServiceProvider, isFalse);
      expect(groceryDelivery.shouldOpenServiceProfile, isFalse);
      expect(groceryDelivery.shopActionLabel, 'Shop Now');

      // 2. Hardware walk-in store
      const hardwareShop = Business(
        id: 'h-1',
        name: 'National Hardware & Tools',
        slug: 'national-hardware',
        categorySlug: 'hardware',
        addressText: 'Industrial Area, Cuttack',
        status: 'approved',
        verificationStatus: 'verified',
        acceptsRequests: true,
      );
      expect(hardwareShop.isServiceProvider, isFalse);
      expect(hardwareShop.shouldOpenServiceProfile, isFalse);
      expect(hardwareShop.shopActionLabel, 'View Store');

      // 3. Medical / Pharmacy
      const pharmacy = Business(
        id: 'm-1',
        name: 'City Meds Pharmacy',
        slug: 'city-meds',
        categorySlug: 'medical',
        addressText: 'Hospital Road, Bhubaneswar',
        status: 'approved',
        verificationStatus: 'verified',
        deliveryEnabled: true,
      );
      expect(pharmacy.isServiceProvider, isFalse);
      expect(pharmacy.shouldOpenServiceProfile, isFalse);
      expect(pharmacy.shopActionLabel, 'Shop Now');

      // 4. Restaurant with delivery
      const restaurantDelivery = Business(
        id: 'r-1',
        name: 'Spice Garden Restaurant',
        slug: 'spice-garden',
        categorySlug: 'restaurant',
        addressText: 'Food Street, Bhubaneswar',
        status: 'approved',
        verificationStatus: 'verified',
        deliveryEnabled: true,
      );
      expect(restaurantDelivery.isServiceProvider, isFalse);
      expect(restaurantDelivery.shouldOpenServiceProfile, isFalse);
      expect(restaurantDelivery.shopActionLabel, 'Order Food');

      // 5. Restaurant dine-in only (no delivery)
      const restaurantDineIn = Business(
        id: 'r-2',
        name: 'Heritage Dhaba',
        slug: 'heritage-dhaba',
        categorySlug: 'restaurant',
        addressText: 'Highway 16, Cuttack',
        status: 'approved',
        verificationStatus: 'verified',
      );
      expect(restaurantDineIn.isServiceProvider, isFalse);
      expect(restaurantDineIn.shouldOpenServiceProfile, isFalse);
      expect(restaurantDineIn.shopActionLabel, 'View Menu');

      // 6. Hotel with booking enabled
      const hotel = Business(
        id: 'ht-1',
        name: 'Grand Bay Resort',
        slug: 'grand-bay',
        categorySlug: 'hotel',
        addressText: 'Marine Drive, Puri',
        status: 'approved',
        verificationStatus: 'verified',
        roomBookingEnabled: true,
      );
      expect(hotel.isServiceProvider, isFalse);
      expect(hotel.shouldOpenServiceProfile, isFalse);
      expect(hotel.shopActionLabel, 'Book Stay');
    });
  });
}
