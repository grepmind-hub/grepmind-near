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

/// 2026 Mint + Emerald redesign of the Customer Cart & Checkout experience.
/// Implements the approved UI showcase mockup with separate Grocery/Food tabs,
/// itemized rows with direct quantity steppers, transparent bill details,
/// and a sticky checkout action footer.
class PlatformCartScreen extends ConsumerStatefulWidget {
  const PlatformCartScreen({super.key, required this.scope});
  final PlatformCartScope scope;

  @override
  ConsumerState<PlatformCartScreen> createState() => _PlatformCartScreenState();
}

class _PlatformCartScreenState extends ConsumerState<PlatformCartScreen> {
  late String _activeVertical;
  CustomerAddress? _address;
  Map<String, dynamic>? _quote;
  bool _busy = false;
  String? _paymentMethod;
  String? _error;
  String? _idempotencyKey;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _activeVertical = widget.scope.vertical;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  PlatformCartScope get _currentScope => PlatformCartScope(
        userId: widget.scope.userId,
        vertical: _activeVertical,
        localityId: widget.scope.localityId,
        locality: widget.scope.locality,
        district: widget.scope.district,
      );

  String _newUUID() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }

  String _money(int minor) => '₹${(minor / 100).toStringAsFixed(0)}';

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
    if (!mounted || selected == null) return;
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
    final cart = ref.read(platformCartProvider(_currentScope));
    if (address == null ||
        address.localityId != _currentScope.localityId ||
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
          .read(platformCartProvider(_currentScope).notifier)
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
          .read(platformCartProvider(_currentScope).notifier)
          .submit(
            quote['quote_id'] as String,
            key,
            _notes.text.trim(),
            paymentMethod: _paymentMethod,
          );
      await ref.read(platformCartProvider(_currentScope).notifier).clear();
      ref.invalidate(customerOrdersProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline_rounded,
            color: AppTheme.emerald,
            size: 48,
          ),
          title: const Text('Order request received'),
          content: Text(
            'Your ${_activeVertical == 'food' ? 'Food' : 'Grocery'} order was sent to the selected fulfillment partner. ${_paymentMethod == 'cash_on_delivery' ? 'Synthetic Cash on Delivery is due at delivery; no cash is collected now.' : 'Sandbox UPI payment is not confirmed yet. Complete it from the order screen; fulfillment starts only after backend verification.'}\n\nReference: ${order['reference_code'] ?? order['id']}',
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.emerald),
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

  void _switchVertical(String vertical) {
    if (_activeVertical == vertical) return;
    setState(() {
      _activeVertical = vertical;
      _quote = null;
      _idempotencyKey = null;
      _paymentMethod = null;
      _error = null;
    });
    if (_address != null) {
      _refreshQuote();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(platformCartProvider(_currentScope));

    return Scaffold(
      backgroundColor: AppTheme.brandCanvas,
      appBar: AppBar(
        backgroundColor: AppTheme.brandCanvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.brandText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Cart',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.brandText,
              ),
            ),
            Text(
              'GrepMind Near · ${_currentScope.locality}, ${_currentScope.district}',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.brandTextMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.brandMint.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_basket_outlined,
              size: 20,
              color: AppTheme.emerald,
            ),
          ),
        ],
      ),
      bottomNavigationBar: cart.isEmpty ? null : _buildStickyCheckoutFooter(cart),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Vertical Segmented Switcher (Grocery vs Food)
            _buildVerticalSwitcher(),
            const SizedBox(height: 14),

            if (!cart.loaded || (_busy && cart.isEmpty))
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppTheme.emerald),
                ),
              )
            else if (cart.isEmpty)
              _buildEmptyCartView()
            else ...[
              // Items List Card
              _buildItemsCard(cart),
              const SizedBox(height: 14),

              // Bill Details Card
              _buildBillDetailsCard(cart),
              const SizedBox(height: 14),

              // Delivery Address Card
              _buildAddressCard(),
              const SizedBox(height: 14),

              // Verified Quote Card (Fulfillment Partner Breakdown)
              if (_quote != null) ...[
                _buildQuoteDetailsCard(),
                const SizedBox(height: 14),
                _buildPaymentMethodCard(),
                const SizedBox(height: 14),
              ],

              // Order Notes
              if (_quote != null) ...[
                TextField(
                  controller: _notes,
                  maxLength: 300,
                  decoration: InputDecoration(
                    labelText: 'Order note (optional)',
                    hintText: 'Add an instruction for delivery or packing',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppTheme.brandBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppTheme.brandBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppTheme.emerald, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Error display
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              const Text(
                'Illustrative interaction with verified local partners. Grepmind Near fulfills orders with double-entry accountability.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.brandTextMuted, fontSize: 11),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEBEFEA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _switcherPill(
              title: 'Grocery',
              active: _activeVertical == 'grocery',
              onTap: () => _switchVertical('grocery'),
            ),
          ),
          Expanded(
            child: _switcherPill(
              title: 'Food',
              active: _activeVertical == 'food',
              onTap: () => _switchVertical('food'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switcherPill({required String title, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x0C17352C),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: active ? AppTheme.brandText : AppTheme.brandTextMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCartView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F6F3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_basket_outlined,
                size: 48,
                color: AppTheme.emerald,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your ${_activeVertical == 'food' ? 'Food' : 'Grocery'} cart is empty',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.brandText,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Browse the verified catalog to add products or meals from local neighborhood partners.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.brandTextMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsCard(PlatformCartState cart) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brandBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0817352C),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < cart.lines.values.length; i++) ...[
            _buildCartLineRow(cart.lines.values.elementAt(i)),
            if (i < cart.lines.values.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F3)),
          ],
        ],
      ),
    );
  }

  Widget _buildCartLineRow(PlatformCartLine line) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Thumbnail / Icon container
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 52,
              height: 52,
              color: const Color(0xFFF1F5F3),
              child: line.imageUrl != null && line.imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: apiClient.resolveMediaUrl(line.imageUrl!),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _linePlaceholder(),
                    )
                  : _linePlaceholder(),
            ),
          ),
          const SizedBox(width: 12),

          // Product Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.brandText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line.variantName.isNotEmpty && line.variantName != line.unitLabel
                      ? '${line.variantName} · ${line.unitLabel}'
                      : line.unitLabel,
                  style: const TextStyle(fontSize: 11, color: AppTheme.brandTextMuted),
                ),
                const SizedBox(height: 3),
                Text(
                  _money(line.priceHintMinor),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.brandText,
                  ),
                ),
              ],
            ),
          ),

          // Stepper: [-] qty [+] with 48dp touch targets
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD1D5DB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _changeCart(
                    () => ref
                        .read(platformCartProvider(_currentScope).notifier)
                        .setQuantity(line.variantId, line.quantity - 1),
                  ),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    alignment: Alignment.center,
                    child: const Icon(Icons.remove, size: 14, color: AppTheme.brandTextMuted),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '${line.quantity}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.brandText,
                    ),
                  ),
                ),
                InkWell(
                  onTap: line.quantity >= 50
                      ? null
                      : () => _changeCart(
                            () => ref
                                .read(platformCartProvider(_currentScope).notifier)
                                .setQuantity(line.variantId, line.quantity + 1),
                          ),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    alignment: Alignment.center,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AppTheme.emerald,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linePlaceholder() {
    return Center(
      child: Icon(
        _activeVertical == 'food' ? Icons.restaurant_rounded : Icons.eco_rounded,
        size: 26,
        color: AppTheme.emerald,
      ),
    );
  }

  Widget _buildBillDetailsCard(PlatformCartState cart) {
    final quote = _quote;
    final itemTotal = quote != null
        ? (quote['item_subtotal_minor'] as num).toInt()
        : cart.subtotalHintMinor;
    final deliveryFee = quote != null
        ? (quote['delivery_fee_minor'] as num).toInt()
        : null;
    final grandTotal = quote != null
        ? (quote['grand_total_minor'] as num).toInt()
        : cart.subtotalHintMinor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brandBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0617352C),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bill details',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.brandText,
            ),
          ),
          const SizedBox(height: 12),

          // Item total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Item total',
                style: TextStyle(fontSize: 13, color: AppTheme.brandTextMuted),
              ),
              Text(
                _money(itemTotal),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Delivery fee
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Delivery and other fees',
                style: TextStyle(fontSize: 13, color: AppTheme.brandTextMuted),
              ),
              Text(
                deliveryFee != null
                    ? (deliveryFee == 0 ? 'FREE' : _money(deliveryFee))
                    : 'Calculated at checkout',
                style: TextStyle(
                  fontSize: 13,
                  color: deliveryFee != null && deliveryFee == 0
                      ? AppTheme.emerald
                      : AppTheme.brandTextMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF1F5F3)),
          ),

          // Items subtotal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                quote != null ? 'Grand total' : 'Items subtotal',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.brandText,
                ),
              ),
              Text(
                _money(grandTotal),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.brandText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8F6F3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB8F2DC)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _chooseAddress,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: AppTheme.emerald,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _address != null ? _address!.label : 'Delivery address',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _address != null
                            ? _address!.formatted
                            : 'Select or confirm your address at checkout',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppTheme.brandTextMuted),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppTheme.emerald,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteDetailsCard() {
    final quote = _quote!;
    final partner = quote['partner'] as Map<String, dynamic>? ?? const {};

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 16, color: AppTheme.emerald),
              const SizedBox(width: 6),
              Text(
                'Fulfilled by ${partner['name'] ?? 'Local Partner'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final raw in quote['items'] as List<dynamic>? ?? const [])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${raw['quantity']} × ${raw['product_name']} · ${_money((raw['unit_price_minor'] as num).toInt() * (raw['quantity'] as num).toInt())}',
                style: const TextStyle(fontSize: 12, color: AppTheme.brandTextMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard() {
    final quote = _quote!;
    final upiAvailable = quote['upi_sandbox_available'] == true;
    final codAvailable = quote['cash_on_delivery_available'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment method',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.brandText,
            ),
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _paymentMethod,
            onChanged: (val) {
              if (val != null) setState(() => _paymentMethod = val);
            },
            child: Column(
              children: [
                if (codAvailable)
                  const RadioListTile<String>(
                    value: 'cash_on_delivery',
                    contentPadding: EdgeInsets.zero,
                    title: Text('Cash on Delivery', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Synthetic COD · due at doorstep handover', style: TextStyle(fontSize: 11)),
                    secondary: Icon(Icons.payments_outlined, color: AppTheme.emerald),
                  ),
                if (upiAvailable)
                  const RadioListTile<String>(
                    value: 'upi',
                    contentPadding: EdgeInsets.zero,
                    title: Text('UPI', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Sandbox simulation payment', style: TextStyle(fontSize: 11)),
                    secondary: Icon(Icons.account_balance_outlined, color: AppTheme.emerald),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyCheckoutFooter(PlatformCartState cart) {
    final total = _quote != null
        ? (_quote!['grand_total_minor'] as num).toInt()
        : cart.subtotalHintMinor;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: AppTheme.emerald,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x28059669),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _busy
                ? null
                : (_quote == null ? _chooseAddress : _submit),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  // Left side: Subtotal & items count
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_money(total)} subtotal',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${cart.itemCount} ${cart.itemCount == 1 ? 'item' : 'items'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Right side: Continue / Place order action
                  if (_busy)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _quote == null ? 'Continue' : 'Place order',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
