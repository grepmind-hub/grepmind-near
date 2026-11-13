import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/customer_address.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/providers/platform_cart_provider.dart';
import 'package:grepmind_mobile/core/screens/customer_addresses_screen.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class PlatformCartScreen extends ConsumerStatefulWidget {
  const PlatformCartScreen({super.key, required this.scope});
  final PlatformCartScope scope;

  @override
  ConsumerState<PlatformCartScreen> createState() => _PlatformCartScreenState();
}

class _PlatformCartScreenState extends ConsumerState<PlatformCartScreen> {
  CustomerAddress? _address;
  Map<String, dynamic>? _quote;
  bool _busy = false;
  String? _paymentMethod;
  String? _error;
  String? _idempotencyKey;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String _newUUID() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }

  String _money(int minor) => '₹${(minor / 100).toStringAsFixed(2)}';

  String _errorMessage(Object error) {
    if (error is DioException) {
      final body = error.response?.data;
      if (body is Map && body['error'] is Map) {
        final detail = body['error'] as Map;
        return (detail['message'] ??
                detail['code'] ??
                'Checkout is unavailable.')
            .toString();
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Network problem. Your cart is saved. Check your connection and retry.';
      }
    }
    return 'Checkout could not be completed. Your cart is saved; please retry.';
  }

  Future<void> _chooseAddress() async {
    final selected = await Navigator.push<CustomerAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => const CustomerAddressesScreen(selectAddress: true),
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    if (selected.localityId != widget.scope.localityId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Choose or add an address in ${widget.scope.locality}, ${widget.scope.district} for this cart.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _address = selected;
      _quote = null;
      _paymentMethod = null;
      _idempotencyKey = null;
      _error = null;
    });
    await _refreshQuote();
  }

  Future<void> _refreshQuote() async {
    final address = _address;
    final cart = ref.read(platformCartProvider(widget.scope));
    if (address == null ||
        address.localityId != widget.scope.localityId ||
        cart.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _quote = null;
    });
    try {
      final quote = await ref
          .read(platformCartProvider(widget.scope).notifier)
          .quote(address.id);
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _paymentMethod = quote['upi_sandbox_available'] == true
            ? 'upi'
            : quote['cash_on_delivery_available'] == true
            ? 'cash_on_delivery'
            : null;
        _idempotencyKey = _newUUID();
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _errorMessage(error);
          _busy = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final quote = _quote;
    final key = _idempotencyKey;
    if (quote == null || key == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await ref
          .read(platformCartProvider(widget.scope).notifier)
          .submit(
            quote['quote_id'] as String,
            key,
            _notes.text.trim(),
            paymentMethod: _paymentMethod,
          );
      await ref.read(platformCartProvider(widget.scope).notifier).clear();
      ref.invalidate(customerOrdersProvider);
      if (!mounted) return;
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
            'Your ${widget.scope.vertical == 'food' ? 'Food' : 'Grocery'} order was sent to the selected fulfillment partner. ${_paymentMethod == 'cash_on_delivery' ? 'Synthetic Cash on Delivery is due at delivery; no cash is collected now.' : 'Sandbox UPI payment is not confirmed yet. Complete it from the order screen; fulfillment starts only after backend verification.'}\n\nReference: ${order['reference_code'] ?? order['id']}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continue to order'),
            ),
          ],
        ),
      );
      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderTrackingScreen(orderId: order['id'] as String),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _errorMessage(error);
          _busy = false;
        });
      }
    }
  }

  Future<void> _changeCart(Future<void> Function() change) async {
    await change();
    if (!mounted) return;
    setState(() {
      _quote = null;
      _idempotencyKey = null;
      _paymentMethod = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(platformCartProvider(widget.scope));
    final title = widget.scope.vertical == 'food'
        ? 'Food cart'
        : 'Grocery cart';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh availability and prices',
            onPressed: _busy || cart.isEmpty ? null : _refreshQuote,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !cart.loaded || _busy && cart.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : cart.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Your cart is empty. Browse the Grepmind catalog to add products.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _locationCard(),
                const SizedBox(height: 12),
                for (final line in cart.lines.values) _lineCard(line),
                const SizedBox(height: 8),
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cart estimate',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${cart.itemCount} items · ${_money(cart.subtotalHintMinor)}',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Estimate only. Final price and partner availability are verified by Grepmind at checkout.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_address != null)
                  Card(
                    color: Colors.white,
                    child: ListTile(
                      leading: const Icon(
                        Icons.location_on_outlined,
                        color: AppTheme.primary,
                      ),
                      title: Text(_address!.label),
                      subtitle: Text(_address!.formatted),
                      trailing: const Icon(Icons.edit_location_alt_outlined),
                      onTap: _chooseAddress,
                    ),
                  ),
                if (_quote != null) _quoteCard(),
                if (_quote != null) _paymentMethodCard(),
                if (_error != null)
                  Card(
                    color: const Color(0xFFFFF1F0),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFB42318)),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                if (_quote == null)
                  FilledButton.icon(
                    onPressed: _busy ? null : _chooseAddress,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(
                      _busy
                          ? 'Checking availability…'
                          : 'Choose address & get verified total',
                    ),
                  )
                else ...[
                  TextField(
                    controller: _notes,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Order note (optional)',
                      hintText: 'Add a short instruction',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy || _paymentMethod == null ? null : _submit,
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      _busy
                          ? 'Placing order…'
                          : 'Place order · ${_money((_quote!['grand_total_minor'] as num).toInt())}',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Payment availability and order eligibility are checked again by Grepmind when you continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.secondaryText),
                ),
              ],
            ),
    );
  }

  Widget _locationCard() => Card(
    color: AppTheme.primaryContainer,
    child: ListTile(
      leading: const Icon(Icons.location_on_outlined, color: AppTheme.primary),
      title: const Text('Delivery locality'),
      subtitle: Text(
        '${widget.scope.locality}, ${widget.scope.district} · ${widget.scope.vertical == 'food' ? 'Food' : 'Grocery'} cart',
      ),
    ),
  );

  Widget _lineCard(PlatformCartLine line) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: line.imageUrl == null
                  ? const ColoredBox(
                      color: AppTheme.surfaceVariant,
                      child: Icon(Icons.shopping_bag_outlined),
                    )
                  : CachedNetworkImage(
                      imageUrl: apiClient.resolveMediaUrl(line.imageUrl!),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: AppTheme.surfaceVariant,
                        child: Icon(Icons.shopping_bag_outlined),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${line.variantName} · ${line.unitLabel}',
                  style: const TextStyle(color: AppTheme.secondaryText),
                ),
                Text(
                  _money(line.priceHintMinor),
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Decrease quantity',
                    onPressed: () => _changeCart(
                      () => ref
                          .read(platformCartProvider(widget.scope).notifier)
                          .setQuantity(line.variantId, line.quantity - 1),
                    ),
                    icon: const Icon(Icons.remove_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    '${line.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    tooltip: 'Increase quantity',
                    onPressed: line.quantity >= 50
                        ? null
                        : () => _changeCart(
                            () => ref
                                .read(
                                  platformCartProvider(widget.scope).notifier,
                                )
                                .setQuantity(line.variantId, line.quantity + 1),
                          ),
                    icon: const Icon(Icons.add_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              TextButton(
                onPressed: () => _changeCart(
                  () => ref
                      .read(platformCartProvider(widget.scope).notifier)
                      .remove(line.variantId),
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _quoteCard() {
    final quote = _quote!;
    final partner = quote['partner'] as Map<String, dynamic>? ?? const {};
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verified checkout',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Fulfilled by ${partner['name'] ?? 'an approved local partner'}',
            ),
            const SizedBox(height: 8),
            for (final raw in quote['items'] as List<dynamic>? ?? const [])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${raw['quantity']} × ${raw['product_name']} · ${raw['variant_name']} — ${_money((raw['unit_price_minor'] as num).toInt() * (raw['quantity'] as num).toInt())}',
                ),
              ),
            const Divider(height: 22),
            _totalRow('Items', (quote['item_subtotal_minor'] as num).toInt()),
            _totalRow(
              'Delivery fee',
              (quote['delivery_fee_minor'] as num).toInt(),
            ),
            _totalRow('Tax', (quote['tax_minor'] as num).toInt()),
            const Divider(height: 22),
            _totalRow(
              'Total',
              (quote['grand_total_minor'] as num).toInt(),
              strong: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Quote expires ${DateTime.parse(quote['expires_at'] as String).toLocal().toString().substring(0, 16)}. Prices and stock are checked again when you place the order.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (quote['tax_status'] == 'not_configured')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Tax is not separately calculated in this build.',
                  style: TextStyle(color: AppTheme.secondaryText),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _paymentMethodCard() {
    final quote = _quote!;
    final upiAvailable = quote['upi_sandbox_available'] == true;
    final codAvailable = quote['cash_on_delivery_available'] == true;
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Payment method',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (upiAvailable || codAvailable)
              RadioGroup<String>(
                groupValue: _paymentMethod,
                onChanged: (value) {
                  if (_busy || value == null) return;
                  setState(() => _paymentMethod = value);
                },
                child: Column(
                  children: [
                    if (upiAvailable)
                      RadioListTile<String>(
                        value: 'upi',
                        enabled: !_busy,
                        title: const Text('UPI'),
                        subtitle: const Text(
                          'Sandbox payment · no real money is charged',
                        ),
                        secondary: const Icon(Icons.account_balance_outlined),
                      ),
                    if (codAvailable)
                      RadioListTile<String>(
                        value: 'cash_on_delivery',
                        enabled: !_busy,
                        title: const Text('Cash on Delivery'),
                        subtitle: Text(
                          'Synthetic QA only · ${_money((quote['grand_total_minor'] as num).toInt())} due at delivery; no cash collected now',
                        ),
                        secondary: const Icon(Icons.payments_outlined),
                      ),
                  ],
                ),
              ),
            if (!upiAvailable && !codAvailable)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No payment method is currently available for this order.',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, int minor, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: strong ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
        ),
        Text(
          _money(minor),
          style: strong
              ? const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                  fontSize: 17,
                )
              : null,
        ),
      ],
    ),
  );
}
