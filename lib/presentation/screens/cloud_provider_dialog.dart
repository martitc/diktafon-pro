import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/providers/gemini/gemini_model_catalog.dart';
import '../../services/providers/chatgpt/chatgpt_connection_probe.dart';
import '../../services/providers/chatgpt/loopback_authorization.dart';

enum CloudSettingsKind { transcription, summary }

class CloudProviderDialog extends ConsumerStatefulWidget {
  const CloudProviderDialog({super.key, required this.kind});
  final CloudSettingsKind kind;

  @override
  ConsumerState<CloudProviderDialog> createState() =>
      _CloudProviderDialogState();
}

class _CloudProviderDialogState extends ConsumerState<CloudProviderDialog> {
  final _key = TextEditingController();
  final _geminiSummaryInstructions = TextEditingController();
  bool _busy = false;
  String? _message;
  List<ProbeModel> _models = [];
  String _geminiModel = 'gemini-2.5-flash';
  String _geminiSummaryModel = 'gemini-2.5-flash';
  String _chatModel = 'gpt-6-luna';
  String _reasoning = 'high';
  String _transcriptionChoice = 'whisper';
  String _summaryChoice = 'local';

  bool get _transcription => widget.kind == CloudSettingsKind.transcription;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    _transcriptionChoice = settings.transcriptionProvider;
    _summaryChoice = settings.summaryProvider;
    _geminiModel = GeminiModelCatalog.byId(settings.geminiModel).id;
    _geminiSummaryModel = GeminiModelCatalog.byId(
      settings.geminiSummaryModel,
    ).id;
    _geminiSummaryInstructions.text = settings.geminiSummaryInstructions;
    _chatModel = settings.chatGptModel;
    _reasoning = settings.chatGptReasoning;
    unawaited(_loadSavedValues());
  }

  Future<void> _loadSavedValues() async {
    final vault = ref.read(credentialVaultProvider);
    _key.text = await vault.readGeminiKey() ?? '';
    if (!_transcription && _summaryChoice == 'chatgpt') {
      final tokens = await vault.readChatGptTokens();
      if (tokens != null) await _refreshModels(tokens);
    }
    if (mounted) setState(() {});
  }

  Future<void> _refreshModels(ProbeTokenSet tokens) async {
    final api = ChatGptConnectionProbe();
    try {
      final current =
          tokens.expiresAt.isBefore(
            DateTime.now().add(const Duration(minutes: 1)),
          )
          ? await api.refresh(tokens)
          : tokens;
      if (current != tokens) {
        await ref.read(credentialVaultProvider).writeChatGptTokens(current);
      }
      final found = await api.listModels(current);
      if (!mounted) return;
      setState(() {
        _models = found;
        if (!_models.any((model) => model.slug == _chatModel)) {
          _chatModel =
              _models
                  .where(
                    (model) => model.slug.toLowerCase().contains('gpt-6-luna'),
                  )
                  .firstOrNull
                  ?.slug ??
              _models.firstOrNull?.slug ??
              _chatModel;
        }
      });
    } on ProbeException {
      if (mounted) {
        setState(
          () => _message =
              'No se pudo actualizar el catálogo de ChatGPT. Vuelve a conectar la cuenta.',
        );
      }
    } finally {
      api.close();
    }
  }

  Future<void> _connectChatGpt() async {
    setState(() {
      _busy = true;
      _message = 'Esperando la autorización del navegador…';
    });
    LoopbackAuthorization? attempt;
    final api = ChatGptConnectionProbe();
    try {
      final hostId = await ref
          .read(credentialVaultProvider)
          .getOrCreateChatGptHostId();
      attempt = await LoopbackAuthorization.start();
      final launched = await launchUrl(
        attempt.authorizationUri(hostId: hostId),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const LoopbackAuthorizationException(
          'No se pudo abrir el navegador.',
        );
      }
      final code = await attempt.result;
      final tokens = await api.exchangeCode(
        code: code.code,
        clientId: code.clientId,
        codeVerifier: attempt.codeVerifier,
        redirectUri: attempt.redirectUri,
        nonce: attempt.nonce,
      );
      final models = await api.listModels(tokens);
      await ref.read(credentialVaultProvider).writeChatGptTokens(tokens);
      if (!mounted) return;
      setState(() {
        _models = models;
        _chatModel =
            models
                .where(
                  (model) => model.slug.toLowerCase().contains('gpt-6-luna'),
                )
                .firstOrNull
                ?.slug ??
            models.firstOrNull?.slug ??
            'gpt-6-luna';
        _message = 'Cuenta conectada. ${models.length} modelos disponibles.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'No se pudo completar la conexión. Revisa la sesión del navegador e inténtalo de nuevo.',
        );
      }
    } finally {
      await attempt?.dispose();
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final repo = ref.read(settingsRepositoryProvider);
    final vault = ref.read(credentialVaultProvider);
    if (_transcription) {
      final key = _key.text.trim();
      if (_transcriptionChoice == 'gemini' && key.isEmpty) {
        setState(
          () => _message =
              'Introduce una clave API de Gemini para seleccionarlo.',
        );
        return;
      }
      if (key.isNotEmpty) await vault.writeGeminiKey(key);
      await repo.setGeminiModel(_geminiModel);
      await repo.setTranscriptionProvider(_transcriptionChoice);
    } else {
      if (_summaryChoice == 'gemini' && _key.text.trim().isEmpty) {
        setState(
          () => _message =
              'Introduce una clave API de Gemini para seleccionarlo.',
        );
        return;
      }
      if (_summaryChoice == 'chatgpt' &&
          await vault.readChatGptTokens() == null) {
        setState(() => _message = 'Conecta primero tu cuenta ChatGPT.');
        return;
      }
      await repo.setChatGptModel(_chatModel);
      await repo.setChatGptReasoning(_reasoning);
      await repo.setSummaryProvider(_summaryChoice);
      if (_summaryChoice == 'gemini') {
        await vault.writeGeminiKey(_key.text.trim());
        await repo.setGeminiSummaryModel(_geminiSummaryModel);
        await repo.setGeminiSummaryInstructions(
          _geminiSummaryInstructions.text,
        );
      }
      if (_summaryChoice != 'local') {
        await repo.setSummariesEnabled(true);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _key.dispose();
    _geminiSummaryInstructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_transcription ? 'Transcripción' : 'Resúmenes'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _transcription
                      ? _transcriptionChoice
                      : _summaryChoice,
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                  items:
                      (_transcription
                              ? const [
                                  ('whisper', 'Whisper local'),
                                  ('gemini', 'Gemini nube'),
                                ]
                              : const [
                                  ('local', 'Qwen local'),
                                  ('gemini', 'Gemini nube'),
                                  ('chatgpt', 'ChatGPT OAuth'),
                                ])
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.$1,
                              child: Text(entry.$2),
                            ),
                          )
                          .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          if (_transcription) {
                            _transcriptionChoice = value!;
                          } else {
                            _summaryChoice = value!;
                          }
                        }),
                ),
                if (_transcription && _transcriptionChoice == 'gemini') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _geminiModel,
                    decoration: const InputDecoration(
                      labelText: 'Modelo Gemini',
                    ),
                    items: [
                      for (final model in GeminiModelCatalog.options)
                        DropdownMenuItem(
                          value: model.id,
                          child: Text(
                            '${model.name.replaceFirst('Gemini ', '').replaceAll(' · voz', '')} · ${model.billingLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _geminiModel = value!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _key,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Clave API Gemini',
                    ),
                  ),
                  if (_key.text.isNotEmpty)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await ref
                                  .read(credentialVaultProvider)
                                  .deleteGeminiKey();
                              setState(() => _key.clear());
                            },
                      child: const Text('Eliminar clave guardada'),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'En Free Tier, Google puede usar el contenido para mejorar sus productos. En el nivel de pago, Google indica que no lo usa con ese fin. La app no puede saber qué nivel de facturación usa tu proyecto; confirma el precio antes de enviar audio.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  if (_geminiModel == 'gemini-3.5-transcribe')
                    Text(
                      'Este modelo añade tiempos por palabra. Google limita esa opción a audios de hasta 30 minutos por solicitud.',
                      style: theme.textTheme.bodySmall,
                    ),
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://ai.google.dev/gemini-api/docs/pricing',
                      ),
                    ),
                    child: const Text('Consultar precios actuales de Google'),
                  ),
                ],
                if (!_transcription && _summaryChoice == 'gemini') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _geminiSummaryModel,
                    decoration: const InputDecoration(
                      labelText: 'Modelo Gemini para resúmenes',
                    ),
                    items: [
                      for (final model in GeminiModelCatalog.options.where(
                        (model) => !model.specialized,
                      ))
                        DropdownMenuItem(
                          value: model.id,
                          child: Text(
                            '${model.name.replaceFirst('Gemini ', '')} · ${model.billingLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _geminiSummaryModel = value!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _key,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Clave API Gemini',
                    ),
                  ),
                  if (_key.text.isNotEmpty)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await ref
                                  .read(credentialVaultProvider)
                                  .deleteGeminiKey();
                              setState(() => _key.clear());
                            },
                      child: const Text('Eliminar clave guardada'),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'El resumen envía a Gemini el texto transcrito y estas instrucciones, no el audio. En Free Tier, Google puede usar el contenido para mejorar sus productos; en el nivel de pago indica que no lo usa con ese fin. La app no puede saber el nivel de facturación del proyecto.',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _geminiSummaryInstructions,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Instrucciones para los resúmenes Gemini',
                    ),
                  ),
                ],
                if (!_transcription && _summaryChoice == 'chatgpt') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _connectChatGpt,
                    icon: const Icon(Icons.open_in_browser),
                    label: Text(
                      _models.isEmpty
                          ? 'Conectar ChatGPT'
                          : 'Actualizar modelos',
                    ),
                  ),
                  if (_models.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue:
                          _models.any((model) => model.slug == _chatModel)
                          ? _chatModel
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Modelo ChatGPT',
                      ),
                      items: [
                        for (final model in _models)
                          DropdownMenuItem(
                            value: model.slug,
                            child: Text(
                              model.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _chatModel = value!),
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _reasoning,
                      decoration: const InputDecoration(
                        labelText: 'Razonamiento',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Bajo')),
                        DropdownMenuItem(value: 'medium', child: Text('Medio')),
                        DropdownMenuItem(value: 'high', child: Text('Alto')),
                      ],
                      onChanged: (value) => setState(() => _reasoning = value!),
                    ),
                    const Text(
                      'ChatGPT OAuth se usa solo para resúmenes. El audio se transcribe localmente o con Gemini.',
                    ),
                  ],
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Conectando…' : 'Guardar'),
        ),
      ],
    );
  }
}
