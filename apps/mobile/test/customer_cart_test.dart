import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/cart_provider.dart';

class _MemoryCartStorage implements CartStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test('business detail preserves backend ordering capabilities', () {
    final detail = BusinessDetail.fromJson(const {
      'id': 'business-1',
      'name': 'Cuttack Kitchen',
      'category_slug': 'restaurant',
      'category_name': 'Restaurant & Food',
      'address_text': 'Cuttack',
      'status': 'approved',
      'verification_status': 'verified',
      'delivery_enabled': true,
      'delivery_time_mins': 35,
      'delivery_fee': 22.5,
      'min_order_amount': 150,
      'table_booking_enabled': true,
      'amenities': ['pickup'],
    });
    expect(detail.deliveryEnabled, isTrue);
    expect(detail.deliveryTimeMins, 35);
    expect(detail.deliveryFee, 22.5);
    expect(detail.minOrderAmount, 150);
    expect(detail.tableBookingEnabled, isTrue);
    expect(detail.amenities, ['pickup']);
    expect(detail.supportsFoodOrdering, isTrue);
    expect(detail.shouldOpenServiceProfile, isFalse);
  });

  test('cart persists per customer and restores item quantities', () async {
    final storage = _MemoryCartStorage();
    final first = CartNotifier(storage: storage);
    await first.loadForUser('customer-a');
    const product = Product(
      id: 'product-1',
      businessId: 'business-1',
      name: 'Coffee',
      price: 125,
      isPublished: true,
      stockStatus: 'in_stock',
    );
    expect(
      await first.addProduct(
        userId: 'customer-a',
        businessId: 'business-1',
        businessName: 'Local Cafe',
        product: product,
      ),
      isTrue,
    );
    await first.addProduct(
      userId: 'customer-a',
      businessId: 'business-1',
      businessName: 'Local Cafe',
      product: product,
    );
    expect(
      await first.addProduct(
        userId: 'customer-a',
        businessId: 'business-2',
        businessName: 'Other Cafe',
        product: const Product(
          id: 'p2',
          businessId: 'business-2',
          name: 'Tea',
          price: 50,
          isPublished: true,
        ),
      ),
      isFalse,
    );
    final restored = CartNotifier(storage: storage);
    await restored.loadForUser('customer-a');
    expect(restored.state.businessId, 'business-1');
    expect(restored.state.lines['product-1']?.quantity, 2);
    expect(restored.state.businessName, 'Local Cafe');
    await restored.setQuantity('product-1', 1);
    expect(restored.state.lines['product-1']?.quantity, 1);
    await restored.remove('product-1');
    expect(restored.state.lines, isEmpty);
    expect(storage.values.containsKey('customer_cart_v1_customer-a'), isFalse);
    await restored.loadForUser('customer-b');
    expect(restored.state.lines, isEmpty);
    first.dispose();
    restored.dispose();
  });

  test('cart validation uses server prices and rejects unavailable or below-minimum cart', () async {
    final storage = _MemoryCartStorage();
    final notifier = CartNotifier(
      storage: storage,
      validator: (_, _) async => {
        'data': {
          'business_name': 'Local Cafe',
          'item_subtotal_minor': 15000,
          'minimum_order_minor': 20000,
          'currency': 'INR',
          'items': [
            {
              'product_id': 'product-1',
              'quantity': 1,
              'name': 'Coffee',
              'unit_price_minor': 15000,
              'available': true,
            },
            {
              'product_id': 'product-2',
              'quantity': 1,
              'available': false,
              'reason': 'insufficient_stock',
            },
          ],
        },
      },
    );
    await notifier.loadForUser('customer-a');
    // Seed a cart through the persistence format to avoid platform plugins.
    storage.values['customer_cart_v1_customer-a'] = jsonEncode({
      'business_id': 'business-1',
      'business_name': 'Local Cafe',
      'lines': [
        const CartLine(
          productId: 'product-1',
          name: 'Coffee',
          quantity: 1,
          priceHintMinor: 12000,
        ).toJson(),
        const CartLine(
          productId: 'product-2',
          name: 'Tea',
          quantity: 1,
          priceHintMinor: 5000,
        ).toJson(),
      ],
    });
    await notifier.loadForUser('customer-b');
    await notifier.loadForUser('customer-a');
    await notifier.validate();
    expect(notifier.state.subtotalMinor, 15000);
    expect(notifier.state.lines['product-1']?.priceHintMinor, 15000);
    expect(notifier.state.validationItems['product-2']?['available'], false);
    expect(notifier.state.isValid, false);
    notifier.dispose();
  });

  test('cart is valid only when each item is available and minimum is met', () {
    const valid = CartState(
      lines: {
        'p': CartLine(
          productId: 'p',
          name: 'Tea',
          quantity: 1,
          priceHintMinor: 500,
        ),
      },
      validationItems: {
        'p': {'available': true},
      },
      subtotalMinor: 500,
      minimumOrderMinor: 400,
    );
    expect(valid.isValid, isTrue);
    expect(
      const CartState(
        lines: {
          'p': CartLine(
            productId: 'p',
            name: 'Tea',
            quantity: 1,
            priceHintMinor: 500,
          ),
        },
        validationItems: {
          'p': {'available': true},
        },
        subtotalMinor: 300,
        minimumOrderMinor: 400,
      ).isValid,
      isFalse,
    );
  });

  test(
    'network failure leaves cart intact and exposes retryable error',
    () async {
      final storage = _MemoryCartStorage();
      final notifier = CartNotifier(
        storage: storage,
        validator: (_, _) async => throw Exception('offline'),
      );
      await notifier.loadForUser('customer-a');
      await notifier.addProduct(
        userId: 'customer-a',
        businessId: 'business-1',
        businessName: 'Cafe',
        product: const Product(
          id: 'p',
          businessId: 'business-1',
          name: 'Coffee',
          price: 60,
          isPublished: true,
        ),
      );
      await notifier.validate();
      expect(notifier.state.lines, hasLength(1));
      expect(notifier.state.isValidating, isFalse);
      expect(notifier.state.validationError, contains('retry'));
      expect(notifier.state.isValid, isFalse);
      notifier.dispose();
    },
  );

  test('finite stock cannot be added beyond the catalog quantity', () async {
    final notifier = CartNotifier(storage: _MemoryCartStorage());
    const product = Product(
      id: 'p',
      businessId: 'b',
      name: 'One left',
      price: 99,
      isPublished: true,
      stockStatus: 'in_stock',
      inventoryMode: 'finite',
      availableQuantity: 1,
    );
    expect(
      await notifier.addProduct(
        userId: 'u',
        businessId: 'b',
        businessName: 'Cafe',
        product: product,
      ),
      isTrue,
    );
    expect(
      await notifier.addProduct(
        userId: 'u',
        businessId: 'b',
        businessName: 'Cafe',
        product: product,
      ),
      isFalse,
    );
    expect(notifier.state.lines['p']?.quantity, 1);
    notifier.dispose();
  });
}
