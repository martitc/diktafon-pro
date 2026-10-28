import 'package:diktafon/application/providers.dart';
import 'package:diktafon/data/db/database.dart';
import 'package:diktafon/data/repositories/settings_repository.dart';
import 'package:diktafon/presentation/screens/cloud_provider_dialog.dart';
import 'package:diktafon/services/providers/credential_vault.dart';
import 'package:diktafon/services/providers/chatgpt/chatgpt_connection_probe.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Vault extends CredentialVault {
  String? geminiKey;

  @override
  Future<String?> readGeminiKey() async => geminiKey;

  @override
  Future<void> writeGeminiKey(String value) async => geminiKey = value;

  @override
  Future<void> deleteGeminiKey() async => geminiKey = null;

  @override
  Future<ProbeTokenSet?> readChatGptTokens() async => null;
}

void main() {
  late AppDatabase db;
  late _Vault vault;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    vault = _Vault();
  });

  tearDown(() => db.close());

  testWidgets('selects Gemini summaries and saves model, key, and prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          credentialVaultProvider.overrideWithValue(vault),
          settingsProvider.overrideWith(
            (ref) => Stream.value(const AppSettings()),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const CloudProviderDialog(
                    kind: CloudSettingsKind.summary,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qwen local'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemini nube').last);
    await tester.pumpAndSettle();

    expect(find.text('Modelo Gemini para resúmenes'), findsOneWidget);
    expect(find.text('Clave API Gemini'), findsOneWidget);
    expect(
      find.text('Instrucciones para los resúmenes Gemini'),
      findsOneWidget,
    );
    expect(
      find.textContaining('el texto transcrito y estas instrucciones'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, 'test-gemini-key');
    final promptField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText ==
              'Instrucciones para los resúmenes Gemini',
    );
    await tester.enterText(promptField, 'Enumera los acuerdos.');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final settings = await SettingsRepository(db).get();
    expect(settings.summaryProvider, 'gemini');
    expect(settings.geminiSummaryModel, 'gemini-2.5-flash');
    expect(settings.geminiSummaryInstructions, 'Enumera los acuerdos.');
    expect(settings.summariesEnabled, isTrue);
    expect(vault.geminiKey, 'test-gemini-key');
  });
}
