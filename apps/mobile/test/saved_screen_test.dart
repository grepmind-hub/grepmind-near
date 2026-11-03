import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/saved_screen.dart';

class FixtureFavoritesNotifier extends FavoritesNotifier {
  FixtureFavoritesNotifier(List<Business> initialItems) {
    state = FavoritesState(items: initialItems);
  }

  @override
  Future<void> load() async {}

  @override
  Future<bool?> toggle(String businessId) async {
    final items = [...state.items];
    final index = items.indexWhere((business) => business.id == businessId);
    if (index >= 0) {
      items.removeAt(index);
      state = state.copyWith(items: items);
      return false;
    }
    return true;
  }

  @override
  Future<bool> clearAll() async {
    state = const FavoritesState();
    return true;
  }
}

const _businessA = Business(
  id: 'business-a',
  name: 'Cuttack Grocery',
  categorySlug: 'grocery',
  categoryName: 'Grocery',
  addressText: 'Badambadi, Cuttack',
  city: 'Cuttack',
  status: 'approved',
  verificationStatus: 'verified',
);

const _businessB = Business(
  id: 'business-b',
  name: 'Cuttack Hardware',
  categorySlug: 'hardware',
  categoryName: 'Hardware',
  addressText: 'Badambadi, Cuttack',
  city: 'Cuttack',
  status: 'approved',
  verificationStatus: 'verified',
);

void main() {
  testWidgets('saved list shows records and removes a single favorite', (
    tester,
  ) async {
    final favorites = FixtureFavoritesNotifier([_businessA, _businessB]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [favoritesProvider.overrideWith((ref) => favorites)],
        child: const MaterialApp(home: SavedScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Cuttack Grocery'), findsOneWidget);
    expect(find.text('Cuttack Hardware'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from saved').first);
    await tester.pump();

    expect(favorites.state.items, hasLength(1));
    expect(favorites.state.items.single.id, 'business-b');
    expect(find.text('Cuttack Grocery'), findsNothing);
  });

  testWidgets('clear all removes saved entries from the provider', (
    tester,
  ) async {
    final favorites = FixtureFavoritesNotifier([_businessA, _businessB]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [favoritesProvider.overrideWith((ref) => favorites)],
        child: const MaterialApp(home: SavedScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove all'));
    await tester.pumpAndSettle();

    expect(favorites.state.items, isEmpty);
    expect(find.text('No saved businesses yet'), findsOneWidget);
  });
}
