import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/widgets/screen_illustration_card.dart';

void main() {
  testWidgets(
    'renders screen illustration and remains usable on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final illustration in ScreenIllustration.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: ScreenIllustrationCard(
                  illustration: illustration,
                  title: 'Illustration preview',
                  subtitle: 'Screen artwork stays inside its panel',
                  icon: Icons.explore_outlined,
                  compact: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Illustration preview'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        expect(tester.takeException(), isNull, reason: illustration.name);
      }
    },
  );
}
