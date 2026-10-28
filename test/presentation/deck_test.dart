import 'package:diktafon/l10n/l10n.dart';
import 'package:diktafon/presentation/theme/theme.dart';
import 'package:diktafon/presentation/widgets/cassette_deck_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'import key is accessible, beside record, and works on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(280, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var importCalls = 0;
      var recordCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: CassetteDeckControls(
                playing: false,
                hasAudio: false,
                importingAudio: false,
                onRewind: () {},
                onPlayPause: () {},
                onForward: () {},
                onImport: () => importCalls++,
                onRecord: () => recordCalls++,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Import audio'), findsOneWidget);
      final importRect = tester.getRect(find.bySemanticsLabel('Import audio'));
      final recordRect = tester.getRect(
        find.bySemanticsLabel('Record a new memo'),
      );
      expect(importRect.center.dx, lessThan(recordRect.center.dx));
      expect(recordRect.left - importRect.right, lessThanOrEqualTo(8));
      await tester.tap(find.bySemanticsLabel('Import audio'));
      await tester.pump();
      expect(importCalls, 1);
      expect(recordCalls, 0);
    },
  );
}
