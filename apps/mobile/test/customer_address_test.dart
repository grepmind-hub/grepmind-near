import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/customer_address.dart';

void main() {
  test('customer address parses map-pin coordinates and formats location', () {
    final address = CustomerAddress.fromJson({
      'id': 'address-1',
      'label': 'Home',
      'recipient_name': 'Riya Das',
      'address_line1': '12 Market Road',
      'locality': 'Badambadi',
      'landmark': 'Near clock tower',
      'city': 'Cuttack',
      'state': 'Odisha',
      'postal_code': '753001',
      'contact_phone': '+919876543210',
      'latitude': 20.501,
      'longitude': 85.901,
      'is_default': true,
    });

    expect(address.isDefault, isTrue);
    expect(address.latitude, 20.501);
    expect(address.longitude, 85.901);
    expect(address.formatted, contains('Badambadi'));
    expect(address.formatted, contains('753001'));
    expect(
      CustomerAddress.fromJson(address.toJson()).formatted,
      address.formatted,
    );
  });

  test('customer address tolerates missing optional pin and landmark', () {
    final address = CustomerAddress.fromJson({
      'id': 'address-2',
      'label': 'Work',
      'recipient_name': 'A',
      'address_line1': '3 Main Street',
      'locality': 'Town',
      'city': 'Jajpur',
      'state': 'Odisha',
      'postal_code': '755001',
      'contact_phone': '+919876543210',
    });

    expect(address.latitude, isNull);
    expect(address.longitude, isNull);
    expect(address.landmark, isEmpty);
    expect(address.formatted, isNot(contains('null')));
  });
}
