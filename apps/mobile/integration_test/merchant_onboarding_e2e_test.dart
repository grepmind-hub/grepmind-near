import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/profile_screen.dart';
import 'package:grepmind_mobile/core/utils/category_sample_image.dart';

/// Full local-only merchant setup journey. The wrapper supplies a new phone
/// number which it has confirmed is absent from the local users table.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fresh OTP merchant registers, uploads media and adds a product', (
    tester,
  ) async {
    const phone = String.fromEnvironment('TEST_PHONE_E164');
    const city = String.fromEnvironment('TEST_CITY');
    const locality = String.fromEnvironment('TEST_LOCALITY');
    const postalCode = String.fromEnvironment('TEST_POSTAL_CODE');
    const address = String.fromEnvironment('TEST_ADDRESS');
    const categorySlug = String.fromEnvironment('TEST_CATEGORY_SLUG');
    const latitude = String.fromEnvironment('TEST_LATITUDE');
    const longitude = String.fromEnvironment('TEST_LONGITUDE');
    const businessNameInput = String.fromEnvironment('TEST_BUSINESS_NAME');
    const businessDescription = String.fromEnvironment(
      'TEST_BUSINESS_DESCRIPTION',
    );
    const productNameInput = String.fromEnvironment('TEST_PRODUCT_NAME');
    const productDescription = String.fromEnvironment(
      'TEST_PRODUCT_DESCRIPTION',
    );
    const productPriceInput = String.fromEnvironment('TEST_PRODUCT_PRICE');
    if (phone.isEmpty ||
        city.isEmpty ||
        locality.isEmpty ||
        postalCode.isEmpty ||
        address.isEmpty ||
        categorySlug.isEmpty ||
        businessNameInput.isEmpty ||
        businessDescription.isEmpty ||
        productNameInput.isEmpty ||
        productDescription.isEmpty ||
        productPriceInput.isEmpty ||
        latitude.isEmpty ||
        longitude.isEmpty) {
      throw StateError(
        'Use scripts/merchant_onboarding_e2e.ps1 to provide a fresh test account and listing details.',
      );
    }
    if (!RegExp(r'^\+91[6-9]\d{9}$').hasMatch(phone) ||
        !const ['Cuttack', 'Jajpur'].contains(city)) {
      throw StateError(
        'The onboarding automation accepts generated Indian test numbers and Cuttack/Jajpur only.',
      );
    }

    apiClient.init();
    apiClient.dio.interceptors
        .clear(); // Never reuse the emulator owner's secure-storage session.
    final otpResponse = await apiClient.post(
      '/auth/otp/request',
      data: {'phone_e164': phone},
    );
    final otp = otpResponse.data['data']['otp_code'] as String?;
    if (otp == null || otp.length != 6) {
      throw StateError(
        'Local OTP disclosure is unavailable; this test never sends SMS.',
      );
    }
    final sessionResponse = await apiClient.post(
      '/auth/otp/verify',
      data: {'phone_e164': phone, 'otp_code': otp},
    );
    final session = sessionResponse.data['data'] as Map<String, dynamic>;
    final accessToken = session['access_token'] as String;
    final user = AppUser.fromJson(session['user'] as Map<String, dynamic>);
    apiClient.dio.options.headers['Authorization'] = 'Bearer $accessToken';

    // Use a bundled category photo as a controlled, truthful QA image fixture.
    final avatarBytes = await cropCategorySample(11);
    final avatar = await apiClient.uploadMedia(
      bytes: avatarBytes,
      filename: 'qa-profile-photo.png',
      purpose: 'avatar',
    );
    final avatarPath = avatar['url'] as String;
    final me = await apiClient.patch(
      '/me',
      data: {
        'display_name': 'QA Merchant ${phone.substring(phone.length - 4)}',
        'avatar_url': avatarPath,
      },
    );
    expect(me.data['data']['avatar_url'], avatarPath);
    final avatarCheck = await apiClient.dio.get<List<int>>(
      apiClient.resolveMediaUrl(avatarPath),
      options: Options(responseType: ResponseType.bytes),
    );
    expect(avatarCheck.statusCode, 200);
    expect(avatarCheck.data, isNotEmpty);

    final provider = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) {
          final notifier = AuthNotifier();
          notifier.state = AuthState(user: user, accessToken: accessToken);
          return notifier;
        }),
      ],
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: provider,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Register / Claim Business'));
    await tester.tap(find.text('Register / Claim Business'));
    await tester.pumpAndSettle();
    expect(find.text('Merchant Onboarding'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('merchant_category_search')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('merchant_category_search')),
      categorySlug.replaceAll('_', ' '),
    );
    await tester.pumpAndSettle();
    final category = find.byKey(ValueKey('merchant_category_$categorySlug'));
    expect(category, findsOneWidget);
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & Continue'));
    await tester.pumpAndSettle();

    final runId = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(
      16,
    );
    await tester.enterText(
      find.byKey(const ValueKey('merchant_business_name')),
      'QA $businessNameInput $runId',
    );
    await tester.enterText(
      find.byKey(const ValueKey('merchant_owner_name')),
      'QA Merchant',
    );
    await tester.enterText(
      find.byKey(const ValueKey('merchant_business_description')),
      'QA fixture: $businessDescription',
    );
    await tester.tap(find.text('Save & Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('merchant_address')),
      address,
    );
    await tester.enterText(
      find.byKey(const ValueKey('merchant_locality')),
      locality,
    );
    await tester.enterText(find.byKey(const ValueKey('merchant_city')), city);
    await tester.enterText(
      find.byKey(const ValueKey('merchant_postal_code')),
      postalCode,
    );
    await tester.ensureVisible(find.text('Enter map coordinates manually'));
    await tester.tap(find.text('Enter map coordinates manually'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('merchant_latitude')),
      latitude,
    );
    await tester.enterText(
      find.byKey(const ValueKey('merchant_longitude')),
      longitude,
    );
    await tester.tap(find.text('Save & Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Application'));
    await tester.pumpAndSettle();
    expect(find.text('Business Application Submitted'), findsOneWidget);

    final profileResponse = await apiClient.get('/merchant/profile');
    final businessId = profileResponse.data['data']['id'] as String;
    expect(profileResponse.data['data']['status'], 'pending');
    final productsBefore = await apiClient.get('/merchant/products');
    final existingProducts = (productsBefore.data['data'] as List)
        .cast<Map<String, dynamic>>();
    expect(existingProducts, isEmpty);
    final productName = 'QA $productNameInput $runId';

    await tester.tap(find.text('Open Merchant Workspace'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Manage Catalog'));
    await tester.tap(find.text('Manage Catalog'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (!provider.read(merchantCatalogProvider).isLoading) break;
    }
    expect(provider.read(merchantCatalogProvider).error, isNull);
    final addButton = find.byKey(const ValueKey('add_product_fab'));
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('modal_product_name')),
      productName,
    );
    await tester.enterText(
      find.byKey(const ValueKey('modal_product_price')),
      productPriceInput,
    );
    await tester.enterText(
      find.byKey(const ValueKey('modal_product_desc')),
      'QA fixture: $productDescription',
    );
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose a sample photo'));
    await tester.tap(find.text('Choose a sample photo'));
    await tester.pumpAndSettle();
    final taxonomy = await apiClient.get('/categories');
    final apiCategories = (taxonomy.data['data'] as List)
        .cast<Map<String, dynamic>>();
    final selectedCategory = apiCategories.singleWhere(
      (item) => item['slug'] == categorySlug,
    );
    final sampleIndex = categorySampleIndex(
      categorySlug,
      selectedCategory['name'] as String,
    );
    final sampleLabel = categorySampleLabels[sampleIndex];
    final sample = find.text(sampleLabel);
    final sampleGrid = find.byKey(const ValueKey('category_sample_grid'));
    final sampleCard = find.byKey(ValueKey('category_sample_$sampleIndex'));
    final sampleScrollable = find.descendant(
      of: sampleGrid,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      sampleCard,
      280,
      scrollable: sampleScrollable,
    );
    expect(sample, findsOneWidget);
    expect(sampleCard, findsOneWidget);
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(sampleCard);
    await tester.pumpAndSettle();
    expect(sampleGrid, findsNothing);
    final saveButton = find.byKey(const ValueKey('save_product_btn'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    for (
      var i = 0;
      i < 300 &&
          find
              .byKey(const ValueKey('modal_product_name'))
              .evaluate()
              .isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('modal_product_name')), findsNothing);
    expect(find.text(productName), findsOneWidget);

    final productsAfter = await apiClient.get('/merchant/products');
    final productRows = (productsAfter.data['data'] as List)
        .cast<Map<String, dynamic>>();
    final saved = productRows.singleWhere((row) => row['name'] == productName);
    expect(saved['business_id'], businessId);
    expect((saved['price'] as num).toDouble(), double.parse(productPriceInput));
    expect(saved['description'], contains(productDescription));
    final imageUrl = saved['image_url'] as String;
    expect(imageUrl, isNotEmpty);
    final productImage = await apiClient.dio.get<List<int>>(
      apiClient.resolveMediaUrl(imageUrl),
      options: Options(responseType: ResponseType.bytes),
    );
    expect(productImage.statusCode, 200);
    expect(productImage.data, isNotEmpty);

    // Emit only a cleanup identifier; tokens, OTPs, and the full phone are never printed.
    // The wrapper derives cleanup from its private manifest/phone value.
    debugPrint(
      'MERCHANT_ONBOARDING_E2E_PASS business=$businessId product=${saved['id']}',
    );
  });
}
