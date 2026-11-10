import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/models/customer_address.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/screens/customer_address_form_screen.dart';

class CustomerAddressesScreen extends StatefulWidget {
  const CustomerAddressesScreen({super.key, this.selectAddress = false});
  final bool selectAddress;

  @override
  State<CustomerAddressesScreen> createState() =>
      _CustomerAddressesScreenState();
}

class _CustomerAddressesScreenState extends State<CustomerAddressesScreen> {
  List<CustomerAddress> _addresses = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await apiClient.get('/customer/addresses');
      final rows = response.data['data'] as List<dynamic>? ?? const [];
      if (!mounted) return;
      setState(() {
        _addresses = rows
            .map((e) => CustomerAddress.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load saved addresses.';
        });
      }
    }
  }

  Future<void> _edit([CustomerAddress? address]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerAddressFormScreen(address: address),
      ),
    );
    if (changed == true) {
      _load();
    }
  }

  Future<void> _delete(CustomerAddress address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text(
          address.isDefault
              ? 'This is your default address. If another address exists, it will become the default.'
              : 'This address will be removed from your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await apiClient.delete('/customer/addresses/${address.id}');
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete address. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: Text(
        widget.selectAddress ? 'Delivery address' : 'Saved addresses',
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Add address'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          )
        : _addresses.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'No saved addresses yet. Add one to continue to delivery checkout.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _addresses.length,
              itemBuilder: (context, index) {
                final address = _addresses[index];
                return Card(
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFD8E2F1)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: widget.selectAddress
                        ? () => Navigator.pop(context, address)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                address.label.toLowerCase() == 'home'
                                    ? Icons.home_outlined
                                    : Icons.location_on_outlined,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  address.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (address.isDefault)
                                const Chip(label: Text('Default')),
                            ],
                          ),
                          Text(
                            address.recipientName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(address.formatted),
                          Text(
                            address.contactPhone,
                            style: const TextStyle(
                              color: AppTheme.secondaryText,
                            ),
                          ),
                          if (address.latitude != null)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'Map pin saved',
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (!widget.selectAddress)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => _edit(address),
                                  child: const Text('Edit'),
                                ),
                                TextButton(
                                  onPressed: () => _delete(address),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
  );
}
