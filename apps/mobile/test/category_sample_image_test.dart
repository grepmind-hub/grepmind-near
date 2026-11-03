import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/utils/category_sample_image.dart';

void main() {
  test(
    'category samples cover the atlas and category aliases map predictably',
    () {
      expect(categorySampleLabels, hasLength(20));
      expect(categorySampleIndex('electrician', 'Electrical Services'), 6);
      expect(categorySampleIndex('books_stationery', 'Books & Stationery'), 12);
      expect(categorySampleIndex('handloom', 'Handloom & Crafts'), 19);
    },
  );

  testWidgets('sample photo widget renders the bundled atlas', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 180,
          height: 120,
          child: CategorySampleImage(index: 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
