import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/providers/platform_cart_provider.dart';
import 'package:grepmind_mobile/core/screens/platform_cart_screen.dart';
import 'package:grepmind_mobile/core/widgets/sticky_cart_summary_bar.dart';

class _FakeMemoryStorage implements PlatformCartStorage {
  final _data = <String, String>{};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async => _data[key] = value;
  @override
  Future<void> delete(String key) async => _data.remove(key);
}

const _testScope = PlatformCartScope(
  userId: 'test-user-1',
  vertical: 'grocery',
  localityId: 'saheed-nagar-loc',
  locality: 'Saheed Nagar',
  district: 'Bhubaneswar',
);

class _TestCartNotifier extends PlatformCartNotifier {
  _TestCartNotifier(super.scope, {required Map<String, PlatformCartLine> initialLines})
      : super(storage: _FakeMemoryStorage()) {
    state = PlatformCartState(lines: initialLines, loaded: true);
  }
}

void main() {
  group('UI Phase 2 — StickyCartSummaryBar', () {
    testWidgets('renders nothing when cart is empty', (tester) async {
      final container = ProviderContainer(
        overrides: [
          platformCartProvider(_testScope).overrideWith(
            (ref) => _TestCartNotifier(_testScope, initialLines: {}),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: StickyCartSummaryBar(scope: _testScope),
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      expect(find.text('View Cart'), findsNothing);
    });

    testWidgets('renders count, subtotal, and View Cart CTA when cart has items', (tester) async {
      final container = ProviderContainer(
        overrides: [
          platformCartProvider(_testScope).overrideWith(
            (ref) => _TestCartNotifier(
              _testScope,
              initialLines: {
                'var-1': const PlatformCartLine(
                  productId: 'prod-1',
                  variantId: 'var-1',
                  productName: 'Fresh Red Tomatoes',
                  variantName: '1 kg',
                  unitLabel: '1 kg',
                  quantity: 2,
                  priceHintMinor: 4200,
                ),
                'var-2': const PlatformCartLine(
                  productId: 'prod-2',
                  variantId: 'var-2',
                  productName: 'Toned Milk',
                  variantName: '500 ml',
                  unitLabel: '500 ml',
                  quantity: 1,
                  priceHintMinor: 2800,
                ),
              },
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: StickyCartSummaryBar(scope: _testScope),
            ),
          ),
        ),
      );

      expect(find.text('3 items'), findsOneWidget);
      expect(find.text('₹112 subtotal'), findsOneWidget);
      expect(find.text('View Cart'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    });
  });

  group('UI Phase 2 — PlatformCartScreen', () {
    testWidgets('renders segmented switcher, items, bill details, and sticky footer', (tester) async {
      final container = ProviderContainer(
        overrides: [
          platformCartProvider(_testScope).overrideWith(
            (ref) => _TestCartNotifier(
              _testScope,
              initialLines: {
                'var-1': const PlatformCartLine(
                  productId: 'prod-1',
                  variantId: 'var-1',
                  productName: 'Fresh Red Tomatoes',
                  variantName: '1 kg',
                  unitLabel: '1 kg',
                  quantity: 2,
                  priceHintMinor: 4200,
                ),
              },
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: PlatformCartScreen(scope: _testScope),
          ),
        ),
      );

      // Header
      expect(find.text('Your Cart'), findsOneWidget);
      expect(find.text('GrepMind Near · Saheed Nagar, Bhubaneswar'), findsOneWidget);

      // Switcher pills
      expect(find.text('Grocery'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);

      // Item details
      expect(find.text('Fresh Red Tomatoes'), findsOneWidget);
      expect(find.text('1 kg'), findsOneWidget);
      expect(find.text('₹42'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Bill details
      expect(find.text('Bill details'), findsOneWidget);
      expect(find.text('Item total'), findsOneWidget);
      expect(find.text('Delivery and other fees'), findsOneWidget);
      expect(find.text('Calculated at checkout'), findsOneWidget);
      expect(find.text('Items subtotal'), findsOneWidget);
      expect(find.text('₹84'), findsNWidgets(2)); // item total & subtotal

      // Address card
      expect(find.text('Delivery address'), findsOneWidget);
      expect(find.text('Select or confirm your address at checkout'), findsOneWidget);

      // Sticky checkout footer
      expect(find.text('₹84 subtotal'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });
  });
}
