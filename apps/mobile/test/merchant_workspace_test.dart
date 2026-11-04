import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';

void main() {
  testWidgets('View Requests quick action opens the requests tab', (
    tester,
  ) async {
    final merchant = _FakeMerchantNotifier();
    final profile = _FakeMerchantProfileNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantProvider.overrideWith((ref) => merchant),
          merchantProfileProvider('').overrideWith((ref) => profile),
        ],
        child: const MaterialApp(home: MerchantWorkspaceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('merchant_view_requests')));
    await tester.tap(find.byKey(const Key('merchant_view_requests')));
    await tester.pumpAndSettle();

    expect(find.text('Request details from QA customer'), findsOneWidget);
  });

  testWidgets('owner can edit and save the business profile', (tester) async {
    final merchant = _FakeMerchantNotifier();
    final profile = _FakeMerchantProfileNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantProvider.overrideWith((ref) => merchant),
          merchantProfileProvider('').overrideWith((ref) => profile),
        ],
        child: const MaterialApp(home: MerchantWorkspaceScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('merchant_edit_business_profile')),
    );
    await tester.tap(find.byKey(const Key('merchant_edit_business_profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('merchant_profile_name')), findsOneWidget);
    expect(find.byKey(const Key('merchant_profile_address')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('merchant_profile_name')),
      'Updated QA Market',
    );
    await tester.tap(find.byKey(const Key('merchant_save_profile')));
    await tester.pumpAndSettle();

    expect(find.text('Updated QA Market'), findsWidgets);
    expect(profile.lastUpdate?['name'], 'Updated QA Market');
  });
}

class _FakeMerchantNotifier extends MerchantNotifier {
  @override
  Future<void> loadRequests() async {
    state = state.copyWith(
      items: const [
        MerchantServiceRequest(
          id: 'qa-request-1',
          customerName: 'QA customer',
          customerPhone: '+919876543210',
          serviceName: 'Pipe repair',
          description: 'Request details from QA customer',
          status: 'requested',
          createdAt: '2026-11-04T08:00:00Z',
          updatedAt: '2026-11-04T08:00:00Z',
        ),
      ],
      isLoading: false,
    );
  }
}

class _FakeMerchantProfileNotifier extends MerchantProfileNotifier {
  _FakeMerchantProfileNotifier() : super('') {
    state = state.copyWith(profile: _profile);
  }

  Map<String, dynamic> _profile = {
    'id': 'qa-business-1',
    'name': 'QA Market',
    'description': 'Sample profile for workspace UI tests.',
    'address_text': 'Market Road',
    'city': 'Cuttack',
    'category_slug': 'grocery',
    'category_name': 'Grocery',
    'phone_e164': '+919876543210',
    'cover_photo_url': '',
    'status': 'approved',
    'verification_status': 'unverified',
    'can_edit_profile': true,
  };
  Map<String, dynamic>? lastUpdate;

  @override
  Future<void> load() async {
    state = state.copyWith(profile: _profile, isLoading: false);
  }

  @override
  Future<bool> update(Map<String, dynamic> updates) async {
    lastUpdate = Map<String, dynamic>.from(updates);
    _profile = {..._profile, ...updates};
    state = state.copyWith(profile: _profile, isLoading: false);
    return true;
  }
}
