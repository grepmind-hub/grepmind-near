import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/cart_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class CustomerCartScreen extends ConsumerStatefulWidget {
  const CustomerCartScreen({super.key});

  @override
  ConsumerState<CustomerCartScreen> createState() => _CustomerCartScreenState();
}

class _CustomerCartScreenState extends ConsumerState<CustomerCartScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(cartProvider.notifier).validate();
    });
  }

  String _money(int minor) => '₹${(minor / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text('Your cart'),
        actions: [
          if (cart.hasLines)
            TextButton(onPressed: notifier.clear, child: const Text('Clear')),
        ],
      ),
      body: !cart.hasLines
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shopping_bag_outlined,
                      size: 56,
                      color: AppTheme.emerald,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your cart is empty',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add orderable items from a nearby restaurant or cafe to get started.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Explore businesses'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: notifier.validate,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE1EBE5)),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFFE8F5E9),
                          child: Icon(
                            Icons.storefront_rounded,
                            color: AppTheme.emerald,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cart.businessName ?? 'Merchant',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text(
                                'Single-merchant cart',
                                style: TextStyle(color: AppTheme.secondaryText),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final line in cart.lines.values)
                    _CartLineCard(
                      line: line,
                      validation: cart.validationItems[line.productId],
                      onDecrement: () => notifier.setQuantity(
                        line.productId,
                        line.quantity - 1,
                      ),
                      onIncrement: () => notifier.setQuantity(
                        line.productId,
                        line.quantity + 1,
                      ),
                      onRemove: () => notifier.remove(line.productId),
                    ),
                  if (cart.isValidating)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (cart.validationError != null)
                    _NoticeCard(
                      message: cart.validationError!,
                      action: TextButton.icon(
                        onPressed: notifier.validate,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                  for (final item in cart.validationItems.values.where(
                    (item) => item['available'] != true,
                  ))
                    _NoticeCard(
                      message:
                          '${item['name'] ?? 'An item'} is unavailable or no longer has enough stock. Remove it to continue.',
                    ),
                  if (cart.subtotalMinor != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE1EBE5)),
                      ),
                      child: Column(
                        children: [
                          _SummaryRow(
                            label: 'Server-verified subtotal',
                            value: _money(cart.subtotalMinor!),
                          ),
                          if (cart.minimumOrderMinor != null &&
                              cart.minimumOrderMinor! > 0) ...[
                            const Divider(height: 24),
                            _SummaryRow(
                              label: 'Merchant minimum',
                              value: _money(cart.minimumOrderMinor!),
                            ),
                            if (cart.subtotalMinor! < cart.minimumOrderMinor!)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Add ${_money(cart.minimumOrderMinor! - cart.subtotalMinor!)} more to meet the minimum order.',
                                  style: const TextStyle(
                                    color: Color(0xFF9A5B00),
                                  ),
                                ),
                              ),
                          ],
                          const SizedBox(height: 8),
                          const Text(
                            'Prices and availability are refreshed from the merchant before continuing.',
                            style: TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: cart.hasLines
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: cart.isValidating || !cart.isValid
                      ? null
                      : () => Navigator.pop(context, true),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Continue to order'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _CartLineCard extends StatelessWidget {
  const _CartLineCard({
    required this.line,
    required this.validation,
    required this.onDecrement,
    required this.onIncrement,
    required this.onRemove,
  });
  final CartLine line;
  final Map<String, dynamic>? validation;
  final VoidCallback onDecrement, onRemove;
  final VoidCallback? onIncrement;
  @override
  Widget build(BuildContext context) {
    final updated = validation?['unit_price_minor'] as int?;
    final unavailable = validation != null && validation!['available'] != true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unavailable
              ? const Color(0xFFFFC7C7)
              : const Color(0xFFE1EBE5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAF9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: line.imageUrl == null || line.imageUrl!.isEmpty
                ? const Icon(
                    Icons.shopping_bag_outlined,
                    color: AppTheme.primary,
                  )
                : CachedNetworkImage(
                    imageUrl: apiClient.resolveMediaUrl(line.imageUrl!),
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppTheme.primary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  updated == null
                      ? 'Price refresh pending'
                      : '₹${(updated / 100).toStringAsFixed(2)} each',
                  style: const TextStyle(color: AppTheme.secondaryText),
                ),
                if (validation?['price_changed'] == true)
                  const Text(
                    'Price updated by merchant',
                    style: TextStyle(
                      color: Color(0xFF9A5B00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (unavailable)
                  const Text(
                    'Unavailable',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove item',
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onDecrement,
                    icon: const Icon(Icons.remove_circle_outline),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                  Text(
                    '${line.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    onPressed: line.quantity >= 50 ? null : onIncrement,
                    icon: const Icon(Icons.add_circle_outline),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message, this.action});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFF754600)),
          ),
        ),
        ?action,
      ],
    ),
  );
}
