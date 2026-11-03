import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/utils/contact_actions.dart';

void main() {
  group('ContactActions', () {
    test('normalizes E.164 phone numbers for WhatsApp links', () {
      expect(
        ContactActions.normalizeWhatsAppNumber('+91 98610-00008'),
        '919861000008',
      );
    });

    test('rejects missing and malformed WhatsApp phone numbers', () {
      expect(ContactActions.normalizeWhatsAppNumber(null), isNull);
      expect(ContactActions.normalizeWhatsAppNumber('not a phone'), isNull);
      expect(ContactActions.normalizeWhatsAppNumber('123'), isNull);
    });

    test(
      'builds dial and WhatsApp links without launching platform apps',
      () async {
        final launched = <Uri>[];
        final actions = ContactActions(
          launcher: (uri) async {
            launched.add(uri);
            return true;
          },
        );

        expect(await actions.call('+919861000008'), isTrue);
        expect(await actions.whatsapp('+91 98610 00008'), isTrue);
        expect(launched.map((uri) => uri.toString()), [
          'tel:+919861000008',
          'https://wa.me/919861000008',
        ]);
      },
    );
  });
}
