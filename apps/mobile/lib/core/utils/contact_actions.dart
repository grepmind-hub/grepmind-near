import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ExternalContactLauncher = Future<bool> Function(Uri uri);

final contactActionsProvider = Provider<ContactActions>(
  (ref) => const ContactActions(),
);

/// Opens business contact links without assuming a phone number or installed app.
class ContactActions {
  const ContactActions({this.launcher});

  final ExternalContactLauncher? launcher;

  static String? normalizeWhatsAppNumber(String? phone) {
    if (phone == null) return null;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8 || digits.length > 15) return null;
    return digits;
  }

  Future<bool> call(String? phone) async {
    final value = phone?.trim();
    if (value == null || value.isEmpty) return false;
    return _launch(Uri(scheme: 'tel', path: value));
  }

  Future<bool> whatsapp(String? phone) async {
    final number = normalizeWhatsAppNumber(phone);
    if (number == null) return false;
    return _launch(Uri.https('wa.me', '/$number'));
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await (launcher ?? _launchExternal)(uri);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
