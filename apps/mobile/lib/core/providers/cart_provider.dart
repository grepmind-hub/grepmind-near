import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

class CartLine {
  final String productId;
  final String name;
  final int quantity;
  final int priceHintMinor;
  final String? imageUrl;

  const CartLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.priceHintMinor,
    this.imageUrl,
  });

  CartLine copyWith({
    int? quantity,
    int? priceHintMinor,
    String? name,
    String? imageUrl,
  }) => CartLine(
    productId: productId,
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    priceHintMinor: priceHintMinor ?? this.priceHintMinor,
    imageUrl: imageUrl ?? this.imageUrl,
  );

  Map<String, Object?> toJson() => {
    'product_id': productId,
    'name': name,
    'quantity': quantity,
    'price_hint_minor': priceHintMinor,
    'image_url': imageUrl,
  };
  factory CartLine.fromJson(Map<String, dynamic> json) => CartLine(
    productId: json['product_id'] as String,
    name: json['name'] as String? ?? 'Product',
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    priceHintMinor: (json['price_hint_minor'] as num?)?.toInt() ?? 0,
    imageUrl: json['image_url'] as String?,
  );
}

class CartState {
  final String? userId;
  final String? businessId;
  final String? businessName;
  final Map<String, CartLine> lines;
  final bool isLoaded;
  final bool isValidating;
  final String? validationError;
  final Map<String, Map<String, dynamic>> validationItems;
  final int? subtotalMinor;
  final int? minimumOrderMinor;
  final String? currency;

  const CartState({
    this.userId,
    this.businessId,
    this.businessName,
    this.lines = const {},
    this.isLoaded = false,
    this.isValidating = false,
    this.validationError,
    this.validationItems = const {},
    this.subtotalMinor,
    this.minimumOrderMinor,
    this.currency,
  });

  int get itemCount => lines.values.fold(0, (sum, line) => sum + line.quantity);
  bool get hasLines => lines.isNotEmpty;
  bool get isValid =>
      validationError == null &&
      subtotalMinor != null &&
      validationItems.length == lines.length &&
      validationItems.values.every((item) => item['available'] == true) &&
      (minimumOrderMinor == null || subtotalMinor! >= minimumOrderMinor!);
}

class ReorderResult {
  final bool ready;
  final String message;
  const ReorderResult(this.ready, this.message);
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier({CartStorage? storage, this.validator})
    : _storage = storage ?? SecureCartStorage(),
      super(const CartState());
  final CartStorage _storage;
  final CartValidator? validator;
  static const _prefix = 'customer_cart_v1_';
  String? _storageKey;
  Timer? _validationDebounce;
  int _validationRevision = 0;

  Future<void> loadForUser(String? userId) async {
    if (userId == null || userId.isEmpty) {
      state = const CartState(isLoaded: true);
      return;
    }
    final key = '$_prefix$userId';
    if (state.userId == userId && state.isLoaded) return;
    _validationRevision++;
    _storageKey = key;
    try {
      final raw = await _storage.read(key);
      if (raw == null) {
        state = CartState(userId: userId, isLoaded: true);
        return;
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final lines = <String, CartLine>{};
      for (final value in (json['lines'] as List<dynamic>? ?? const [])) {
        final line = CartLine.fromJson(value as Map<String, dynamic>);
        if (line.quantity > 0 && line.quantity <= 50) {
          lines[line.productId] = line;
        }
      }
      state = CartState(
        userId: userId,
        businessId: json['business_id'] as String?,
        businessName: json['business_name'] as String?,
        lines: lines,
        isLoaded: true,
      );
      if (lines.isEmpty) await _persist();
    } catch (_) {
      await _storage.delete(key);
      state = CartState(userId: userId, isLoaded: true);
    }
  }

  Future<bool> addProduct({
    required String userId,
    required String businessId,
    required String businessName,
    required Product product,
    bool replaceExisting = false,
  }) async {
    await loadForUser(userId);
    if (product.businessId != businessId ||
        !product.isPublished ||
        product.price == null ||
        product.stockStatus == 'out_of_stock') {
      return false;
    }
    if (state.businessId != null &&
        state.businessId != businessId &&
        state.hasLines &&
        !replaceExisting) {
      return false;
    }
    if ((state.lines[product.id]?.quantity ?? 0) >= 50) {
      return false;
    }
    _validationRevision++;
    if (product.inventoryMode == 'finite' &&
        (product.availableQuantity ?? 0) <=
            (state.lines[product.id]?.quantity ?? 0)) {
      return false;
    }
    final lines = state.businessId != businessId
        ? <String, CartLine>{}
        : Map<String, CartLine>.from(state.lines);
    final previous = lines[product.id];
    final minor = ((product.price! * 100).round());
    lines[product.id] = CartLine(
      productId: product.id,
      name: product.name,
      quantity: (previous?.quantity ?? 0) + 1,
      priceHintMinor: minor,
      imageUrl: product.imageUrl,
    );
    state = CartState(
      userId: userId,
      businessId: businessId,
      businessName: businessName,
      lines: lines,
      isLoaded: true,
    );
    await _persist();
    return true;
  }

  Future<void> setQuantity(String productId, int quantity) async {
    if (!state.lines.containsKey(productId)) return;
    if (quantity <= 0) return remove(productId);
    if (quantity > 50) return;
    _validationRevision++;
    final lines = Map<String, CartLine>.from(state.lines);
    lines[productId] = lines[productId]!.copyWith(quantity: quantity);
    _setLines(lines);
    await _persist();
    _scheduleValidation();
  }

  Future<void> remove(String productId) async {
    _validationRevision++;
    final lines = Map<String, CartLine>.from(state.lines)..remove(productId);
    _setLines(lines);
    await _persist();
    if (lines.isNotEmpty) _scheduleValidation();
  }

  Future<void> clear() async {
    _validationRevision++;
    state = CartState(userId: state.userId, isLoaded: true);
    await _persist();
  }

  Future<ReorderResult> rebuildFromOrder({
    required String userId,
    required String businessId,
    required String businessName,
    required List<Map<String, dynamic>> items,
    bool replaceExisting = false,
  }) async {
    await loadForUser(userId);
    if (state.hasLines && state.businessId != businessId && !replaceExisting) {
      return const ReorderResult(
        false,
        'Another merchant cart is already active.',
      );
    }
    if (items.isEmpty || items.length > 50) {
      return const ReorderResult(
        false,
        'This order has no reorderable products.',
      );
    }
    try {
      final responseData = validator == null
          ? (await apiClient.post(
                  '/businesses/$businessId/cart/validate',
                  data: {'items': items},
                )).data
                as Map<String, dynamic>
          : await validator!(businessId, {'items': items});
      final data = responseData['data'] as Map<String, dynamic>;
      final validated = <String, Map<String, dynamic>>{};
      final newLines = <String, CartLine>{};
      final unavailable = <String>[];
      final requestedNames = {
        for (final requested in items)
          requested['product_id'] as String:
              requested['name'] as String? ?? 'An item',
      };
      for (final raw in data['items'] as List<dynamic>) {
        final item = Map<String, dynamic>.from(raw as Map<String, dynamic>);
        final productId = item['product_id'] as String;
        validated[productId] = item;
        if (item['available'] != true) {
          unavailable.add(
            item['name'] as String? ?? requestedNames[productId]!,
          );
          continue;
        }
        final quantity = (item['quantity'] as num).toInt();
        final price = (item['unit_price_minor'] as num).toInt();
        newLines[productId] = CartLine(
          productId: productId,
          name: item['name'] as String? ?? 'Product',
          quantity: quantity,
          priceHintMinor: price,
        );
      }
      final minimumMet = data['minimum_met'] as bool? ?? false;
      if (unavailable.isNotEmpty ||
          !minimumMet ||
          newLines.length != items.length) {
        final reason = unavailable.isNotEmpty
            ? 'Unavailable items: ${unavailable.join(', ')}.'
            : 'The current prices no longer meet this merchant’s minimum order.';
        return ReorderResult(
          false,
          '$reason Review the current catalog and add items again.',
        );
      }
      state = CartState(
        userId: userId,
        businessId: businessId,
        businessName: data['business_name'] as String? ?? businessName,
        lines: newLines,
        isLoaded: true,
        validationItems: validated,
        subtotalMinor: (data['item_subtotal_minor'] as num).toInt(),
        minimumOrderMinor: (data['minimum_order_minor'] as num).toInt(),
        currency: data['currency'] as String?,
      );
      await _persist();
      return const ReorderResult(
        true,
        'Current availability and prices were checked.',
      );
    } catch (_) {
      return const ReorderResult(
        false,
        'Could not revalidate this order. Check your connection and retry.',
      );
    }
  }

  void _setLines(Map<String, CartLine> lines) {
    state = CartState(
      userId: state.userId,
      businessId: lines.isEmpty ? null : state.businessId,
      businessName: lines.isEmpty ? null : state.businessName,
      lines: lines,
      isLoaded: true,
      minimumOrderMinor: state.minimumOrderMinor,
      currency: state.currency,
    );
  }

  Future<void> _persist() async {
    final key = _storageKey;
    if (key == null) return;
    if (state.lines.isEmpty) {
      await _storage.delete(key);
      return;
    }
    await _storage.write(
      key,
      jsonEncode({
        'business_id': state.businessId,
        'business_name': state.businessName,
        'lines': state.lines.values.map((line) => line.toJson()).toList(),
      }),
    );
  }

  Future<void> validate() async {
    if (!state.hasLines || state.businessId == null) return;
    final revision = ++_validationRevision;
    final businessId = state.businessId!;
    final requestedLines = Map<String, CartLine>.from(state.lines);
    state = CartState(
      userId: state.userId,
      businessId: state.businessId,
      businessName: state.businessName,
      lines: state.lines,
      isLoaded: true,
      isValidating: true,
    );
    try {
      final payload = {
        'items': requestedLines.values
            .map(
              (line) => {
                'product_id': line.productId,
                'quantity': line.quantity,
              },
            )
            .toList(),
      };
      final responseData = validator == null
          ? (await apiClient.post(
                  '/businesses/$businessId/cart/validate',
                  data: payload,
                )).data
                as Map<String, dynamic>
          : await validator!(businessId, payload);
      if (revision != _validationRevision) return;
      final data = responseData['data'] as Map<String, dynamic>;
      final items = <String, Map<String, dynamic>>{};
      for (final raw in data['items'] as List<dynamic>) {
        final item = Map<String, dynamic>.from(raw as Map<String, dynamic>);
        final id = item['product_id'] as String;
        final serverPrice = (item['unit_price_minor'] as num?)?.toInt();
        item['price_changed'] =
            serverPrice != null &&
            state.lines[id] != null &&
            serverPrice != state.lines[id]!.priceHintMinor;
        items[id] = item;
        if (serverPrice != null && state.lines[id] != null) {
          final lines = Map<String, CartLine>.from(state.lines)
            ..[id] = state.lines[id]!.copyWith(
              priceHintMinor: serverPrice,
              name: item['name'] as String?,
            );
          state = CartState(
            userId: state.userId,
            businessId: state.businessId,
            businessName: state.businessName,
            lines: lines,
            isLoaded: true,
            isValidating: true,
          );
        }
      }
      final lines = state.lines;
      state = CartState(
        userId: state.userId,
        businessId: state.businessId,
        businessName: data['business_name'] as String? ?? state.businessName,
        lines: lines,
        isLoaded: true,
        validationItems: items,
        subtotalMinor: (data['item_subtotal_minor'] as num).toInt(),
        minimumOrderMinor: (data['minimum_order_minor'] as num).toInt(),
        currency: data['currency'] as String?,
      );
      await _persist();
    } catch (error) {
      if (revision != _validationRevision) return;
      var message =
          'Could not refresh prices and availability. Check your connection and retry.';
      if (error is DioException &&
          error.response?.data is Map<String, dynamic>) {
        final body = error.response!.data as Map<String, dynamic>;
        final apiError = body['error'] as Map<String, dynamic>?;
        if (apiError?['code'] == 'ORDERING_UNAVAILABLE') {
          message = 'This business no longer supports product ordering. Your cart is saved; remove these items or return later.';
        } else {
          message = apiError?['message'] as String? ?? message;
        }
      }
      state = CartState(
        userId: state.userId,
        businessId: state.businessId,
        businessName: state.businessName,
        lines: state.lines,
        isLoaded: true,
        validationError: message,
      );
    }
  }

  void _scheduleValidation() {
    _validationDebounce?.cancel();
    _validationDebounce = Timer(const Duration(milliseconds: 450), validate);
  }

  @override
  void dispose() {
    _validationDebounce?.cancel();
    super.dispose();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier(),
);

abstract interface class CartStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCartStorage implements CartStorage {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

typedef CartValidator = Future<Map<String, dynamic>> Function(
  String businessId,
  Map<String, dynamic> payload,
);
