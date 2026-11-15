import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/customer_address.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/cart_provider.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/screens/customer_addresses_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class CheckoutReviewScreen extends ConsumerStatefulWidget {
  const CheckoutReviewScreen({
    super.key,
    required this.businessId,
    required this.businessName,
  });
  final String businessId, businessName;

  @override
  ConsumerState<CheckoutReviewScreen> createState() =>
      _CheckoutReviewScreenState();
}

class _CheckoutReviewScreenState extends ConsumerState<CheckoutReviewScreen> {
  CustomerAddress? _address;
  Map<String, dynamic>? _quote;
  bool _delivery = true, _quoting = false, _submitting = false;
  bool _submissionUncertain = false;
  String? _error, _quoteIdempotencyKey;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDefaultAddress());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String _key() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> _loadDefaultAddress() async {
    try {
      final response = await apiClient.get('/customer/addresses');
      final rows = response.data['data'] as List<dynamic>? ?? const [];
      if (rows.isNotEmpty && mounted) {
        final values = rows
            .map((v) => CustomerAddress.fromJson(v as Map<String, dynamic>))
            .toList();
        setState(
          () => _address = values.firstWhere(
            (a) => a.isDefault,
            orElse: () => values.first,
          ),
        );
      }
    } catch (_) {
      /* Address screen surfaces the actionable error on demand. */
    }
    if (mounted && (!_delivery || _address != null)) {
      _refreshQuote();
    }
  }

  Future<void> _chooseAddress() async {
    final selected = await Navigator.push<CustomerAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => const CustomerAddressesScreen(selectAddress: true),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _address = selected;
        _quote = null;
        _submissionUncertain = false;
      });
      await _refreshQuote();
    }
  }

  Future<void> _refreshQuote() async {
    final cart = ref.read(cartProvider);
    if (cart.lines.isEmpty || (_delivery && _address == null)) {
      setState(() {
        _quote = null;
        _error = _delivery
            ? 'Add or select a delivery address to check serviceability.'
            : null;
      });
      return;
    }
    setState(() {
      _quoting = true;
      _error = null;
      _quote = null;
    });
    try {
      final response = await apiClient.post(
        '/businesses/${widget.businessId}/orders/quote',
        data: {
          'fulfillment_type': _delivery ? 'delivery' : 'takeaway',
          if (_delivery) 'address_id': _address!.id,
          'items': cart.lines.values
              .map(
                (line) => {
                  'product_id': line.productId,
                  'quantity': line.quantity,
                },
              )
              .toList(),
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _quote = Map<String, dynamic>.from(response.data['data'] as Map);
        _quoteIdempotencyKey = _key();
        _quoting = false;
        _submissionUncertain = false;
      });
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = _message(e);
          _quoting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not get current checkout pricing. Try again.';
          _quoting = false;
        });
      }
    }
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return (err['message'] ?? err['code'] ?? 'Checkout is unavailable.')
          .toString();
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Network problem. Check your connection and retry.';
    }
    return 'Checkout could not be priced. Refresh and try again.';
  }

  int _amount(String key) => (_quote?[key] as num?)?.toInt() ?? 0;
  String _money(int minor) => '₹${(minor / 100).toStringAsFixed(2)}';

  Future<void> _submit() async {
    final quote = _quote;
    if (quote == null || _quoteIdempotencyKey == null) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final order = await ref.read(customerOrdersProvider.notifier).createOrder(
        widget.businessId,
        {
          'order_type': 'food_delivery',
          'checkout_quote_id': quote['quote_id'],
          'fulfillment_type': _delivery ? 'delivery' : 'takeaway',
          'notes': _notes.text.trim(),
        },
        idempotencyKey: _quoteIdempotencyKey,
      );
      await ref.read(cartProvider.notifier).clear();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline_rounded,
            color: AppTheme.primary,
            size: 48,
          ),
          title: const Text('Order request received'),
          content: Text(
            'Your request was sent to ${widget.businessName}. No payment was collected. You can view the request in Orders.\n\nReference: ${order.id.substring(0, 8).toUpperCase()}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = _message(e);
          _submitting = false;
          _submissionUncertain =
              e.response == null || (e.response?.statusCode ?? 0) >= 500;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Order submission could not be confirmed. Retry safely; the same request key will prevent duplicates.';
          _submitting = false;
          _submissionUncertain = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Review order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.businessName,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Delivery'),
                icon: Icon(Icons.delivery_dining_outlined),
              ),
              ButtonSegment(
                value: false,
                label: Text('Takeaway'),
                icon: Icon(Icons.shopping_bag_outlined),
              ),
            ],
            selected: {_delivery},
            onSelectionChanged: (value) {
              setState(() {
                _delivery = value.first;
                _quote = null;
                _error = null;
              });
              if (!_delivery || _address != null) {
                _refreshQuote();
              }
            },
          ),
          if (_delivery) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFD8E2F1)),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.location_on_outlined,
                  color: AppTheme.primary,
                ),
                title: Text(_address?.label ?? 'Choose delivery address'),
                subtitle: Text(
                  _address?.formatted ??
                      'Coverage will be checked by the merchant service.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _chooseAddress,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your items',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  for (final line in cart.lines.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${line.quantity} × ${line.name}'),
                          ),
                          Text(
                            _quote == null
                                ? '—'
                                : _money(
                                    quoteLineAmount(
                                          quote: _quote,
                                          productId: line.productId,
                                          fallback: line.priceHintMinor,
                                        ) *
                                        line.quantity,
                                  ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_quoting)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_quote != null)
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row('Item subtotal', _amount('item_subtotal_minor')),
                    _row('Discount', _amount('discount_minor')),
                    _row('Delivery fee', _amount('delivery_fee_minor')),
                    _row('Tax', _amount('tax_minor')),
                    const Divider(height: 22),
                    _row('Total', _amount('grand_total_minor'), bold: true),
                    if (_amount('minimum_order_minor') > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Merchant minimum: ${_money(_amount('minimum_order_minor'))}',
                            style: const TextStyle(
                              color: AppTheme.secondaryText,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      (_quote?['tax_message'] ??
                              'Prices and availability are verified by the merchant server.')
                          .toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                    Text(
                      'Quote valid until ${_quote?['expires_at'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_quote != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLength: 250,
              decoration: const InputDecoration(
                labelText: 'Special instructions (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline, color: AppTheme.primary),
              title: Text(
                'Payment is unavailable',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'This order request does not collect money or confirm payment.',
              ),
            ),
          ],
          if (_error != null)
            Card(
              color: const Color(0xFFFFF3F0),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFF9D2B20)),
                      ),
                    ),
                    TextButton(
                      onPressed: _quoting || _submitting
                          ? null
                          : (_submissionUncertain ? _submit : _refreshQuote),
                      child: Text(
                        _submissionUncertain
                            ? 'Retry same order'
                            : 'Refresh quote',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_quote == null && !_quoting && _error == null)
            TextButton.icon(
              onPressed: _refreshQuote,
              icon: const Icon(Icons.refresh),
              label: const Text('Get server price'),
            ),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.emerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _quote == null || _quoting || _submitting
                ? null
                : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send order request'),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, int value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
        Text(
          _money(value),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            fontSize: bold ? 17 : null,
          ),
        ),
      ],
    ),
  );

  int quoteLineAmount({
    Map<String, dynamic>? quote,
    required String productId,
    required int fallback,
  }) {
    final items = quote?['items'];
    if (items is List) {
      for (final item in items) {
        if (item is Map && item['product_id'] == productId) {
          return (item['unit_price_minor'] as num?)?.toInt() ?? fallback;
        }
      }
    }
    return fallback;
  }
}
