import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:grepmind_mobile/core/models/customer_address.dart';
import 'package:grepmind_mobile/core/models/platform_catalog.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

class CustomerAddressFormScreen extends StatefulWidget {
  const CustomerAddressFormScreen({super.key, this.address});
  final CustomerAddress? address;
  @override
  State<CustomerAddressFormScreen> createState() =>
      _CustomerAddressFormScreenState();
}

class _CustomerAddressFormScreenState extends State<CustomerAddressFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  String _city = 'Cuttack';
  String _localityId = '';
  List<DeliveryDistrict> _deliveryDistricts = const [];
  bool _loadingDeliveryLocations = true;
  bool _isDefault = false, _saving = false;
  LatLng? _pin;

  @override
  void initState() {
    super.initState();
    final a = widget.address;
    _city = a?.city ?? 'Cuttack';
    _localityId = a?.localityId ?? '';
    _isDefault = a?.isDefault ?? false;
    _pin = a?.latitude == null || a?.longitude == null
        ? null
        : LatLng(a!.latitude!, a.longitude!);
    _fields = {
      for (final entry in <String, String>{
        'label': a?.label ?? 'Home',
        'recipient_name': a?.recipientName ?? '',
        'address_line1': a?.addressLine1 ?? '',
        'locality': a?.locality ?? '',
        'landmark': a?.landmark ?? '',
        'state': a?.state ?? 'Odisha',
        'postal_code': a?.postalCode ?? '',
        'contact_phone': a?.contactPhone ?? '',
      }.entries)
        entry.key: TextEditingController(text: entry.value),
    };
    _loadDeliveryLocations();
  }

  Future<void> _loadDeliveryLocations() async {
    try {
      final response = await apiClient.get('/catalog/locations');
      final rows = response.data['data'] as List<dynamic>? ?? const [];
      if (!mounted) return;
      setState(() {
        _deliveryDistricts = rows
            .whereType<Map<String, dynamic>>()
            .map(DeliveryDistrict.fromJson)
            .toList(growable: false);
        _loadingDeliveryLocations = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDeliveryLocations = false);
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPin() async {
    final selected = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => _AddressMapPicker(initial: _pin, city: _city),
      ),
    );
    if (selected != null && mounted) setState(() => _pin = selected);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final payload = {
      for (final e in _fields.entries) e.key: e.value.text.trim(),
      'city': _city,
      if (_localityId.isNotEmpty) 'locality_id': _localityId,
      'is_default': _isDefault,
      'latitude': _pin?.latitude,
      'longitude': _pin?.longitude,
    };
    try {
      final a = widget.address;
      if (a == null) {
        await apiClient.post('/customer/addresses', data: payload);
      } else {
        await apiClient.put('/customer/addresses/${a.id}', data: payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Address could not be saved. Check your connection and details.',
            ),
          ),
        );
      }
    }
  }

  Widget _field(
    String key,
    String label, {
    TextInputType? keyboard,
    String? Function(String?)? validator,
    bool required = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: _fields[key],
      keyboardType: keyboard,
      validator:
          validator ??
          (required
              ? (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null
              : null),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: Text(widget.address == null ? 'Add address' : 'Edit address'),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _city,
            decoration: const InputDecoration(labelText: 'City'),
            items: const [
              DropdownMenuItem(value: 'Cuttack', child: Text('Cuttack')),
              DropdownMenuItem(value: 'Jajpur', child: Text('Jajpur')),
            ],
            onChanged: (v) => setState(() {
              _city = v ?? _city;
              final belongs = _deliveryDistricts.any(
                (d) =>
                    d.name == _city &&
                    d.localities.any((l) => l.id == _localityId),
              );
              if (!belongs) _localityId = '';
            }),
          ),
          const SizedBox(height: 12),
          _field('label', 'Address label'),
          _field('recipient_name', 'Recipient name'),
          _field('address_line1', 'House / building / street'),
          _field('locality', 'Locality'),
          const SizedBox(height: 4),
          if (_loadingDeliveryLocations)
            const LinearProgressIndicator()
          else ...[
            DropdownButtonFormField<String>(
              initialValue:
                  _deliveryDistricts
                      .where((d) => d.name == _city)
                      .expand((d) => d.localities)
                      .any((l) => l.id == _localityId)
                  ? _localityId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Grepmind delivery locality (optional)',
                helperText: 'Required to check Food and Grocery delivery.',
              ),
              items: [
                for (final district in _deliveryDistricts.where(
                  (d) => d.name == _city,
                ))
                  for (final locality in district.localities.where(
                    (l) => l.deliveryEnabled,
                  ))
                    DropdownMenuItem(
                      value: locality.id,
                      child: Text(locality.name),
                    ),
              ],
              onChanged: (id) {
                final locality = _deliveryDistricts
                    .where((d) => d.name == _city)
                    .expand((d) => d.localities)
                    .where((l) => l.id == id)
                    .firstOrNull;
                setState(() {
                  _localityId = id ?? '';
                  if (locality != null) {
                    _fields['locality']!.text = locality.name;
                  }
                });
              },
            ),
          ],
          _field('landmark', 'Landmark (optional)', required: false),
          _field(
            'postal_code',
            'PIN code',
            keyboard: TextInputType.number,
            validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '')
                ? null
                : 'Enter a 6-digit PIN code',
          ),
          _field(
            'contact_phone',
            'Contact mobile number',
            keyboard: TextInputType.phone,
            validator: (v) =>
                RegExp(r'^(\+91)?[6-9]\d{9}$')
                    .hasMatch((v ?? '').replaceAll(' ', ''))
                ? null
                : 'Enter a valid Indian mobile number',
          ),
          _field('state', 'State'),
          Card(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(Icons.map_outlined, color: AppTheme.primary),
              title: Text(
                _pin == null ? 'Add map pin (optional)' : 'Map pin saved',
              ),
              subtitle: Text(
                _pin == null
                    ? 'Manual address entry is supported'
                    : '${_pin!.latitude.toStringAsFixed(5)}, ${_pin!.longitude.toStringAsFixed(5)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickPin,
            ),
          ),
          SwitchListTile(
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
            title: const Text('Make this my default address'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save address'),
          ),
        ],
      ),
    ),
  );
}

class _AddressMapPicker extends StatefulWidget {
  const _AddressMapPicker({this.initial, required this.city});
  final LatLng? initial;
  final String city;
  @override
  State<_AddressMapPicker> createState() => _AddressMapPickerState();
}

class _AddressMapPickerState extends State<_AddressMapPicker> {
  late LatLng _pin =
      widget.initial ??
      (widget.city == 'Jajpur'
          ? const LatLng(20.85, 86.33)
          : const LatLng(20.46, 85.88));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pin delivery location')),
    body: GoogleMap(
      initialCameraPosition: CameraPosition(target: _pin, zoom: 14),
      onTap: (p) => setState(() => _pin = p),
      markers: {Marker(markerId: const MarkerId('selected'), position: _pin)},
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: () => Navigator.pop(context, _pin),
          child: const Text('Use this location'),
        ),
      ),
    ),
  );
}
