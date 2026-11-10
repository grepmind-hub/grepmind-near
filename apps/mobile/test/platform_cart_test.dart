import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/platform_catalog.dart';
import 'package:grepmind_mobile/core/providers/platform_cart_provider.dart';

class _MemoryStorage implements PlatformCartStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _DelayedStorage extends _MemoryStorage {
  final gate = Completer<void>();

  @override
  Future<String?> read(String key) async {
    await gate.future;
    return super.read(key);
  }
}

const _scope = PlatformCartScope(
  userId: 'customer-a',
  vertical: 'food',
  localityId: 'kuanpal-id',
  locality: 'Kuanpal',
  district: 'Cuttack',
);

const _product = PlatformCatalogProduct(
  id: 'food-product',
  sku: 'QA-FOOD',
  categoryId: 'food-category',
  categoryName: 'Meals',
  categorySlug: 'meals',
  vertical: 'food',
  name: 'Veg Thali',
  description: '',
  variants: [
    PlatformCatalogVariant(
      id: 'variant-1',
      name: 'Regular',
      unitLabel: 'plate',
      priceMinor: 12500,
      currency: 'INR',
      priceRevision: 1,
    ),
    PlatformCatalogVariant(
      id: 'inactive-variant',
      name: 'Retired',
      unitLabel: 'plate',
      priceMinor: 100,
      currency: 'INR',
      priceRevision: 1,
      isActive: false,
    ),
  ],
);

void main() {
  test('first add waits for persisted cart restoration', () async {
    final storage = _DelayedStorage();
    final cart = PlatformCartNotifier(_scope, storage: storage);

    final add = cart.add(_product, _product.variants.first);
    expect(cart.state.loaded, isFalse);
    storage.gate.complete();

    expect(await add, isTrue);
    expect(cart.state.itemCount, 1);
    cart.dispose();
  });

  test('cart persists, restores, and changes quantities per scope', () async {
    final storage = _MemoryStorage();
    final cart = PlatformCartNotifier(_scope, storage: storage);
    await cart.load();
    expect(await cart.add(_product, _product.variants.first), isTrue);
    expect(await cart.add(_product, _product.variants.first), isTrue);
    expect(cart.state.itemCount, 2);

    final restored = PlatformCartNotifier(_scope, storage: storage);
    await restored.load();
    expect(restored.state.lines['variant-1']?.quantity, 2);
    expect(restored.state.subtotalHintMinor, 25000);

    await restored.setQuantity('variant-1', 4);
    expect(restored.state.lines['variant-1']?.quantity, 4);
    await restored.remove('variant-1');
    expect(restored.state.isEmpty, isTrue);

    final otherCustomer = PlatformCartNotifier(
      const PlatformCartScope(
        userId: 'customer-b',
        vertical: 'food',
        localityId: 'kuanpal-id',
        locality: 'Kuanpal',
        district: 'Cuttack',
      ),
      storage: storage,
    );
    await otherCustomer.load();
    expect(otherCustomer.state.isEmpty, isTrue);

    final groceries = PlatformCartNotifier(
      const PlatformCartScope(
        userId: 'customer-a',
        vertical: 'grocery',
        localityId: 'kuanpal-id',
        locality: 'Kuanpal',
        district: 'Cuttack',
      ),
      storage: storage,
    );
    await groceries.load();
    expect(groceries.state.isEmpty, isTrue);
    expect(
      storage.values.keys,
      isNot(contains('platform_cart_v1_customer-a_grocery_kuanpal-id')),
    );

    cart.dispose();
    restored.dispose();
    otherCustomer.dispose();
    groceries.dispose();
  });

  test(
    'rejects wrong vertical, inactive variant, and quantity beyond cap',
    () async {
      final storage = _MemoryStorage();
      final cart = PlatformCartNotifier(_scope, storage: storage);
      await cart.load();
      expect(await cart.add(_product, _product.variants.last), isFalse);
      expect(
        await cart.add(
          const PlatformCatalogProduct(
            id: 'grocery',
            sku: '',
            categoryId: '',
            categoryName: '',
            categorySlug: '',
            vertical: 'grocery',
            name: 'Rice',
            description: '',
          ),
          _product.variants.first,
        ),
        isFalse,
      );
      await cart.add(_product, _product.variants.first);
      await cart.setQuantity('variant-1', 51);
      expect(cart.state.lines['variant-1']?.quantity, 1);
      expect(
        jsonDecode(
          storage.values.values.single,
        )['lines'].single['price_hint_minor'],
        12500,
      );
      cart.dispose();
    },
  );
}
