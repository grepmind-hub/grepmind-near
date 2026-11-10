import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:grepmind_mobile/core/models/platform_catalog.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

class PlatformCartScope {
  const PlatformCartScope({
    required this.userId,
    required this.vertical,
    required this.localityId,
    required this.locality,
    required this.district,
  });

  final String userId, vertical, localityId, locality, district;

  @override
  bool operator ==(Object other) =>
      other is PlatformCartScope &&
      other.userId == userId &&
      other.vertical == vertical &&
      other.localityId == localityId;

  @override
  int get hashCode => Object.hash(userId, vertical, localityId);
}

class PlatformCartLine {
  const PlatformCartLine({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.unitLabel,
    required this.quantity,
    required this.priceHintMinor,
    this.imageUrl,
  });

  final String productId, variantId, productName, variantName, unitLabel;
  final int quantity, priceHintMinor;
  final String? imageUrl;

  PlatformCartLine withQuantity(int value) => PlatformCartLine(
    productId: productId,
    variantId: variantId,
    productName: productName,
    variantName: variantName,
    unitLabel: unitLabel,
    quantity: value,
    priceHintMinor: priceHintMinor,
    imageUrl: imageUrl,
  );

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'variant_id': variantId,
    'product_name': productName,
    'variant_name': variantName,
    'unit_label': unitLabel,
    'quantity': quantity,
    'price_hint_minor': priceHintMinor,
    'image_url': imageUrl,
  };

  factory PlatformCartLine.fromJson(Map<String, dynamic> json) =>
      PlatformCartLine(
        productId: json['product_id'] as String,
        variantId: json['variant_id'] as String,
        productName: json['product_name'] as String? ?? 'Product',
        variantName: json['variant_name'] as String? ?? '',
        unitLabel: json['unit_label'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        priceHintMinor: (json['price_hint_minor'] as num?)?.toInt() ?? 0,
        imageUrl: json['image_url'] as String?,
      );
}

class PlatformCartState {
  const PlatformCartState({this.lines = const {}, this.loaded = false});
  final Map<String, PlatformCartLine> lines;
  final bool loaded;
  int get itemCount => lines.values.fold(0, (sum, line) => sum + line.quantity);
  int get subtotalHintMinor => lines.values.fold(
    0,
    (sum, line) => sum + line.quantity * line.priceHintMinor,
  );
  bool get isEmpty => lines.isEmpty;
}

abstract interface class PlatformCartStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecurePlatformCartStorage implements PlatformCartStorage {
  const SecurePlatformCartStorage();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class PlatformCartNotifier extends StateNotifier<PlatformCartState> {
  PlatformCartNotifier(this.scope, {PlatformCartStorage? storage})
    : _storage = storage ?? const SecurePlatformCartStorage(),
      super(const PlatformCartState()) {
    _loadFuture = _restore();
  }

  final PlatformCartScope scope;
  final PlatformCartStorage _storage;
  Future<void>? _loadFuture;
  String get _key =>
      'platform_cart_v1_${scope.userId}_${scope.vertical}_${scope.localityId}';

  Future<void> load() => _loadFuture ??= _restore();

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(_key);
      final lines = <String, PlatformCartLine>{};
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final value in decoded['lines'] as List<dynamic>? ?? const []) {
          final line = PlatformCartLine.fromJson(value as Map<String, dynamic>);
          if (line.quantity > 0 && line.quantity <= 50) {
            lines[line.variantId] = line;
          }
        }
      }
      state = PlatformCartState(lines: lines, loaded: true);
    } catch (_) {
      await _storage.delete(_key);
      state = const PlatformCartState(loaded: true);
    }
  }

  Future<bool> add(
    PlatformCatalogProduct product,
    PlatformCatalogVariant variant,
  ) async {
    // The product detail screen can be tapped before secure storage finishes
    // restoring this customer's cart. Wait for that restore so the first tap
    // is not silently rejected (and cannot race with a later restore overwrite).
    await load();
    if (product.vertical != scope.vertical ||
        scope.localityId.isEmpty ||
        !product.variants.any(
          (item) => item.id == variant.id && item.isActive,
        ) ||
        variant.priceMinor < 0) {
      return false;
    }
    final previous = state.lines[variant.id];
    if ((previous?.quantity ?? 0) >= 50) return false;
    final lines = Map<String, PlatformCartLine>.from(state.lines);
    lines[variant.id] = PlatformCartLine(
      productId: product.id,
      variantId: variant.id,
      productName: product.name,
      variantName: variant.name,
      unitLabel: variant.unitLabel,
      quantity: (previous?.quantity ?? 0) + 1,
      priceHintMinor: variant.priceMinor,
      imageUrl: product.imageUrls.isEmpty ? null : product.imageUrls.first,
    );
    state = PlatformCartState(lines: lines, loaded: true);
    await _persist();
    return true;
  }

  Future<void> setQuantity(String variantId, int quantity) async {
    final current = state.lines[variantId];
    if (current == null) return;
    if (quantity <= 0) return remove(variantId);
    if (quantity > 50) return;
    final lines = Map<String, PlatformCartLine>.from(state.lines)
      ..[variantId] = current.withQuantity(quantity);
    state = PlatformCartState(lines: lines, loaded: true);
    await _persist();
  }

  Future<void> remove(String variantId) async {
    final lines = Map<String, PlatformCartLine>.from(state.lines)
      ..remove(variantId);
    state = PlatformCartState(lines: lines, loaded: true);
    await _persist();
  }

  Future<void> clear() async {
    state = const PlatformCartState(loaded: true);
    await _storage.delete(_key);
  }

  Future<Map<String, dynamic>> quote(String addressId) async {
    final response = await apiClient.post(
      '/platform/orders/quote',
      data: {
        'vertical': scope.vertical,
        'address_id': addressId,
        'items': state.lines.values
            .map(
              (line) => {
                'variant_id': line.variantId,
                'quantity': line.quantity,
              },
            )
            .toList(),
      },
    );
    return Map<String, dynamic>.from(response.data['data'] as Map);
  }

  Future<Map<String, dynamic>> submit(
    String quoteId,
    String idempotencyKey,
    String notes,
  ) async {
    final response = await apiClient.post(
      '/platform/orders',
      data: {'quote_id': quoteId, 'notes': notes},
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return Map<String, dynamic>.from(response.data['data'] as Map);
  }

  Future<void> _persist() async {
    if (state.lines.isEmpty) return _storage.delete(_key);
    await _storage.write(
      _key,
      jsonEncode({
        'lines': state.lines.values.map((line) => line.toJson()).toList(),
      }),
    );
  }
}

final platformCartProvider =
    StateNotifierProvider.family<
      PlatformCartNotifier,
      PlatformCartState,
      PlatformCartScope
    >((ref, scope) => PlatformCartNotifier(scope));
