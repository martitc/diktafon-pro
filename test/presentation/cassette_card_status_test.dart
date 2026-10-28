import 'package:diktafon/data/repositories/cassette_repository.dart';
import 'package:diktafon/domain/models.dart';
import 'package:diktafon/l10n/gen/app_localizations.dart';
import 'package:diktafon/presentation/widgets/cassette_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CassetteOverview overview() => CassetteOverview(
    cassette: Cassette(
      id: 'cassette-1',
      label: 'Test cassette',
      titleIsUserSet: true,
      colorSeed: 1,
      summary: null,
      summaryUpdatedAt: null,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    memoCount: 3,
    totalDurationMs: 1000,
  );

  Widget host({
    required int readyCount,
    bool isProcessing = false,
    bool hasFailure = false,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 200,
          // Match the home grid's 94×72 card cell: art plus status content.
          height: 200 * 72 / 94,
          child: CassetteCard(
            overview: overview(),
            readyCount: readyCount,
            isProcessing: isProcessing,
            hasFailure: hasFailure,
          ),
        ),
      ),
    ),
  );

  testWidgets('shows a live activity state without a made-up percentage', (
    tester,
  ) async {
    await tester.pumpWidget(host(readyCount: 1, isProcessing: true));

    expect(find.text('1/3 ready'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
  });

  testWidgets('shows full green completion only when every memo is ready', (
    tester,
  ) async {
    await tester.pumpWidget(host(readyCount: 3));

    expect(find.text('3/3 ready'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
  });

  testWidgets('marks failures while keeping the total memo count visible', (
    tester,
  ) async {
    await tester.pumpWidget(host(readyCount: 1, hasFailure: true));

    expect(find.text('1/3 ready'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
  });

  testWidgets('ready status fits inside the home grid cell', (tester) async {
    await tester.pumpWidget(host(readyCount: 3));

    expect(tester.takeException(), isNull);
  });
}
