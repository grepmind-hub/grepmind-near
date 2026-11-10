class CustomerAddress {
  const CustomerAddress({
    required this.id,
    required this.label,
    required this.recipientName,
    required this.addressLine1,
    required this.locality,
    required this.landmark,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.contactPhone,
    required this.isDefault,
    this.localityId,
    this.latitude,
    this.longitude,
  });

  final String id, label, recipientName, addressLine1, locality, landmark;
  final String? localityId;
  final String city, state, postalCode, contactPhone;
  final bool isDefault;
  final double? latitude, longitude;

  factory CustomerAddress.fromJson(Map<String, dynamic> json) =>
      CustomerAddress(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Address',
        recipientName: json['recipient_name'] as String? ?? '',
        addressLine1: json['address_line1'] as String? ?? '',
        locality: json['locality'] as String? ?? '',
        localityId: json['locality_id'] as String?,
        landmark: json['landmark'] as String? ?? '',
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        postalCode: json['postal_code'] as String? ?? '',
        contactPhone: json['contact_phone'] as String? ?? '',
        isDefault: json['is_default'] as bool? ?? false,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'recipient_name': recipientName,
    'address_line1': addressLine1,
    'locality': locality,
    if (localityId != null) 'locality_id': localityId,
    'landmark': landmark,
    'city': city,
    'state': state,
    'postal_code': postalCode,
    'contact_phone': contactPhone,
    'is_default': isDefault,
    'latitude': latitude,
    'longitude': longitude,
  };

  String get formatted => [
    addressLine1,
    locality,
    if (landmark.isNotEmpty) landmark,
    city,
    state,
    postalCode,
  ].join(', ');
}
