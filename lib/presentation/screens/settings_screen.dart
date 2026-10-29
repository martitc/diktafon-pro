import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/l10n.dart';
import '../../services/providers/llm/llm_model_manager.dart';
import '../../services/providers/gemini/gemini_model_catalog.dart';
import '../../services/providers/model_manager.dart';
import '../../services/providers/transcription_provider.dart';
import '../../services/providers/whisper/whisper_model_manager.dart';
import '../../services/system/device_ram.dart';
import '../theme/tape_colors.dart';
import '../widgets/content_width.dart';
import '../widgets/directional_chevrons.dart';
import '../widgets/ink_progress_bar.dart';
import '../widgets/ink_toggle.dart';
import '../widgets/settings_rows.dart';
import 'backup_screen.dart';
import 'cloud_provider_dialog.dart';

/// Settings (§5.5, mockup 05): grouped ink-bordered cards, rectangular
/// toggles. Model & backup rows are honest about what ships in M1.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Endonyms on purpose — a language list reads best in its own words.
  /// Keys are what `appLanguage` stores (D8) — bare whisper codes.
  static const languages = <String, String>{
    'en': 'English',
    'fr': 'Français',
    'es': 'Español',
    'pt': 'Português',
    'de': 'Deutsch',
    'pl': 'Polski',
    'cs': 'Čeština',
    'tr': 'Türkçe',
    'ru': 'Русский',
    'ko': '한국어',
    'it': 'Italiano',
    'id': 'Bahasa Indonesia',
    'uk': 'Українська',
    'vi': 'Tiếng Việt',
    'ja': '日本語',
    // D8 amendment: two script rows, one whisper language — both force
    // whisper-`zh`; the stored value carries the content-script preference.
    'zh-Hans': '中文（简体）',
    'zh-Hant': '中文（繁體）',
    'ar': 'العربية',
    'fa': 'فارسی',
    'hi': 'हिन्दी',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final repo = ref.read(settingsRepositoryProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(backChevron(context), size: 28),
          tooltip: l10n.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.settingsTitle),
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SettingsGroup(
              title: l10n.groupLanguage,
              rows: [
                SettingsRow(
                  title: l10n.transcriptionLanguage,
                  value: settings.appLanguage == null
                      ? l10n.autoDetectValue
                      : languages[settings.appLanguage] ??
                            settings.appLanguage!,
                  onTap: () => _pickLanguage(context, repo, settings),
                ),
              ],
            ),
            SettingsGroup(
              title: l10n.groupPlayback,
              rows: [
                SettingsRow(
                  title: l10n.boundaryChime,
                  value: l10n.boundaryChimeDesc,
                  trailing: InkToggle(
                    value: settings.chimeEnabled,
                    onChanged: repo.setChimeEnabled,
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: l10n.groupIntelligence,
              rows: [
                SettingsRow(
                  title: 'Proveedor de transcripción',
                  value: settings.transcriptionProvider == 'gemini'
                      ? 'Gemini nube · ${settings.geminiModel}'
                      : 'Whisper local · ${settings.whisperTier}',
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => const CloudProviderDialog(
                      kind: CloudSettingsKind.transcription,
                    ),
                  ),
                ),
                SettingsRow(
                  title: l10n.transcriptionModel,
                  value: _whisperRowValue(context, ref, settings),
                  onTap: () => _pickModel(context, const ModelPickerDialog()),
                ),
                SettingsRow(
                  title: 'Proveedor de resúmenes',
                  value: switch (settings.summaryProvider) {
                    'gemini' =>
                      'Gemini nube · ${GeminiModelCatalog.byId(settings.geminiSummaryModel).name}',
                    'chatgpt' =>
                      'ChatGPT OAuth · ${settings.chatGptModel} (${settings.chatGptReasoning})',
                    _ =>
                      'Modelo local · ${LlmModel.byTier(settings.llmTier).label}',
                  },
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => const CloudProviderDialog(
                      kind: CloudSettingsKind.summary,
                    ),
                  ),
                ),
                if (settings.summaryProvider == 'local')
                  SettingsRow(
                    title: l10n.summaryModel,
                    value: _llmRowValue(context, ref, settings),
                    onTap: () =>
                        _pickModel(context, const LlmModelPickerDialog()),
                  ),
              ],
            ),
            if (settings.summaryProvider == 'local')
              SettingsGroup(
                title: l10n.localSummaryInstructionsGroup,
                rows: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    child: LocalSummaryInstructionsField(
                      value: settings.localSummaryInstructions,
                      onChanged: (value) async {
                        try {
                          await repo.setLocalSummaryInstructions(value);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.localSummarySaveFailed),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            SettingsGroup(
              title: l10n.groupAppearance,
              rows: [
                SettingsRow(
                  title: l10n.themeRow,
                  value: switch (settings.theme) {
                    'light' => l10n.themeLight,
                    'dark' => l10n.themeDark,
                    _ => l10n.themeSystem,
                  },
                  onTap: () => _pickTheme(context, repo, settings),
                ),
              ],
            ),
            SettingsGroup(
              title: l10n.groupYourData,
              rows: [
                SettingsRow(
                  title: l10n.backupExport,
                  value: l10n.backupExportDesc,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BackupScreen()),
                  ),
                ),
                SettingsRow(
                  title: l10n.aboutPrivacy,
                  value: l10n.aboutPrivacyDesc,
                  onTap: () => _about(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    SettingsRepository repo,
    AppSettings s,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.l10n.transcriptionLanguageTitle),
        children: [
          _dialogOption(
            dialogContext,
            label: context.l10n.autoDetectOption,
            selected: s.appLanguage == null,
            result: 'auto',
          ),
          for (final entry in languages.entries)
            _dialogOption(
              dialogContext,
              label: entry.value,
              selected: s.appLanguage == entry.key,
              result: entry.key,
            ),
        ],
      ),
    );
    if (choice != null) {
      await repo.setAppLanguage(choice == 'auto' ? null : choice);
    }
  }

  Future<void> _pickTheme(
    BuildContext context,
    SettingsRepository repo,
    AppSettings s,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.l10n.themeTitle),
        children: [
          for (final (value, label) in [
            ('system', context.l10n.themeSystem),
            ('light', context.l10n.themeLight),
            ('dark', context.l10n.themeDark),
          ])
            _dialogOption(
              dialogContext,
              label: label,
              selected: s.theme == value,
              result: value,
            ),
        ],
      ),
    );
    if (choice != null) await repo.setTheme(choice);
  }

  Widget _dialogOption(
    BuildContext context, {
    required String label,
    required bool selected,
    required String result,
  }) => SimpleDialogOption(
    onPressed: () => Navigator.pop(context, result),
    child: Row(
      children: [
        SizedBox(
          width: 22,
          child: selected
              ? Icon(Icons.check, size: 16, color: context.tape.ink)
              : null,
        ),
        // Expanded so long options ("Auto-detect (per memo)" and its
        // translations) wrap instead of overflowing the dialog row.
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : null,
              color: context.tape.ink,
            ),
          ),
        ),
      ],
    ),
  );

  /// "Whisper small · 181 MB — installed", "… downloading 42 %", or a nudge
  /// to set it up (§14 guides the user here while memos wait).
  String _whisperRowValue(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final model = WhisperModel.byTier(settings.whisperTier);
    return _modelRowValue(
      context,
      model,
      ref.watch(whisperModelStatesProvider).value,
      model.sizeLabel,
    );
  }

  String _llmRowValue(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    // Summaries are switched off inside the picker (its first option);
    // the row mirrors that choice instead of a model's install state —
    // keeping the "tap to set up" affordance the other states carry.
    if (!settings.summariesEnabled) return context.l10n.summariesOffValue;
    final model = LlmModel.byTier(settings.llmTier);
    return _modelRowValue(
      context,
      model,
      ref.watch(llmModelStatesProvider).value,
      model.sizeLabel,
    );
  }

  String _modelRowValue(
    BuildContext context,
    ModelSpec model,
    List<ModelState<ModelSpec>>? states,
    String sizeLabel,
  ) {
    final state = states?.where((s) => s.model.tier == model.tier).firstOrNull;
    return switch (state?.status ?? ModelStatus.notInstalled) {
      ModelStatus.ready => context.l10n.modelInstalled(model.label, sizeLabel),
      ModelStatus.downloading => context.l10n.modelDownloading(
        model.label,
        (state!.progress * 100).round(),
      ),
      ModelStatus.paused => context.l10n.modelPaused(
        model.label,
        (state!.progress * 100).round(),
      ),
      _ => context.l10n.modelNotDownloaded(model.label),
    };
  }

  void _pickModel(BuildContext context, Widget dialog) {
    showDialog<void>(context: context, builder: (_) => dialog);
  }

  static final _repoUrl = Uri.parse('https://github.com/martitc/diktafon-pro');
  // The same document the store listings point at (Play console & App Store
  // Connect privacy policy URL).
  static final _privacyUrl = Uri.parse(
    'https://github.com/martitc/diktafon-pro/blob/main/PRIVACY.md',
  );

  void _about(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.aboutTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.aboutBody),
              const SizedBox(height: 14),
              Text(context.l10n.aboutOpenSource),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => launchUrl(_repoUrl),
                child: Text(
                  'github.com/martitc/diktafon-pro',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    color: dialogContext.tape.ink,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () => launchUrl(_privacyUrl),
                child: Text(
                  context.l10n.aboutPrivacyPolicy,
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    color: dialogContext.tape.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.ok),
          ),
        ],
      ),
    );
  }
}

class LocalSummaryInstructionsField extends StatefulWidget {
  const LocalSummaryInstructionsField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final Future<void> Function(String value) onChanged;

  @override
  State<LocalSummaryInstructionsField> createState() =>
      _LocalSummaryInstructionsFieldState();
}

class _LocalSummaryInstructionsFieldState
    extends State<LocalSummaryInstructionsField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant LocalSummaryInstructionsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _controller,
        minLines: 3,
        maxLines: 5,
        maxLength: 2000,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: context.l10n.localSummaryInstructionsTitle,
          hintText: context.l10n.localSummaryInstructionsHint,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => unawaited(widget.onChanged(value)),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          context.l10n.localSummaryInstructionsPrivacy,
          style: TextStyle(fontSize: 10, color: context.tape.ink2),
        ),
      ),
    ],
  );
}

/// Soft device gate for heavyweight tiers (§6.6): total RAM where
/// /proc/meminfo exists (Linux/Android), sysctl on iOS; unknown platforms
/// don't block. The thresholds transfer to iOS as-is: they were calibrated
/// as "model needs ≈ half the device's RAM", which matches the ~50–60 % of
/// physical RAM jetsam lets an iOS app touch — revisit after a device pass.
bool deviceHasRamGb(int gb) {
  if (gb <= 0) return true;
  final bytes = devicePhysicalRamBytes();
  return bytes == null || bytes >= gb * 1024 * 1024 * 1024;
}

/// The transcription-model picker (§5.5, mockup 05 note 3): choose the tier,
/// download with progress, manage storage. Selecting an uninstalled tier
/// starts its download immediately; when it lands, queued memos transcribe.
class ModelPickerDialog extends ConsumerWidget {
  const ModelPickerDialog({super.key});

  /// Turbo is gated at 5 GB total RAM; full Large-v3 is gated at 8 GB.
  static bool deviceCanRun(WhisperModel model) => switch (model.tier) {
    'large-v3-turbo' => deviceHasRamGb(5),
    'large-v3' => deviceHasRamGb(8),
    _ => true,
  };

  /// Device-aware tier copy (§6.6, revised with the §6.3a quality bench):
  /// where the RAM gate passes, large-v3-turbo is the recommended tier —
  /// the bench measured roughly half small's error rate, and the gap widens
  /// on noisy recordings. Below the gate small keeps the recommendation and
  /// large carries the RAM note. Listed tiers read localized copy from the
  /// ARBs; unlisted test tiers keep their dev-only catalog text.
  static String describe(
    AppLocalizations l10n,
    WhisperModel model, {
    required bool largeCapable,
  }) {
    if (model.tier == WhisperModel.small.tier) {
      return largeCapable
          ? l10n.whisperSmallDescCapable
          : l10n.whisperSmallDesc;
    }
    if (model.tier == WhisperModel.largeV3Turbo.tier) {
      return largeCapable
          ? l10n.whisperLargeDescCapable
          : l10n.whisperLargeDesc;
    }
    if (model.tier == WhisperModel.largeV3.tier) {
      return largeCapable
          ? l10n.whisperFullLargeDesc
          : l10n.whisperFullLargeDescBlocked;
    }
    return model.description;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final states = ref.watch(whisperModelStatesProvider).value ?? const [];
    final manager = ref.read(whisperModelManagerProvider);
    return _EnginePickerDialog(
      title: context.l10n.modelPickerTranscriptionTitle,
      states: states,
      selectedTier: settings.whisperTier,
      enabledOf: (model) => deviceCanRun(model as WhisperModel),
      disabledReasonOf: (model) => context.l10n.needsRam(
        (model as WhisperModel).tier == 'large-v3' ? 8 : 5,
      ),
      descriptionOf: (model) => describe(
        context.l10n,
        model as WhisperModel,
        largeCapable: deviceCanRun(model),
      ),
      installedBytes: manager.installedBytes(),
      onSelect: (state) => _select(context, ref, state),
      onDelete: (state) => manager.delete(state.model as WhisperModel),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    ModelState<ModelSpec> state,
  ) async {
    final repo = ref.read(settingsRepositoryProvider);
    final manager = ref.read(whisperModelManagerProvider);
    // Tapping the tier already on the wire pauses it (metered-connection
    // escape hatch); the next tap resumes through the download path below.
    if (state.status == ModelStatus.downloading) {
      manager.pause(state.model as WhisperModel);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    await repo.setWhisperTier(state.model.tier);
    manager.cancelExcept(state.model.tier);
    await downloadAndDrain(
      messenger,
      ref,
      state,
      download: () => manager.download(state.model as WhisperModel),
      readyMessage: l10n.modelReadyTranscribe(state.model.label),
      failedMessage: l10n.downloadFailed(state.model.label),
    );
  }
}

/// The summary-model picker (§5.5 Summaries): same mechanics over the LLM
/// catalog; when a model lands, parked summary jobs resume. Its first row
/// is "No summaries" — the summaries on/off switch lives here, next to the
/// models it governs: picking the off row parks summary jobs, picking any
/// model turns summaries back on.
class LlmModelPickerDialog extends ConsumerWidget {
  const LlmModelPickerDialog({super.key});

  /// Listed tiers read localized copy from the ARBs; unlisted test tiers
  /// keep their dev-only catalog text.
  static String describe(AppLocalizations l10n, LlmModel model) {
    if (model.tier == LlmModel.qwen3_1_7b.tier) return l10n.llmDefaultDesc;
    if (model.tier == LlmModel.qwen3_4b.tier) return l10n.llm4bDesc;
    if (model.tier == LlmModel.gemma4E2b.tier ||
        model.tier == LlmModel.gemma4E4b.tier ||
        model.tier == LlmModel.qwen3_5_2b.tier) {
      return l10n.llmModelDetails(
        model.quantization,
        model.license,
        model.minRamGb,
      );
    }
    return model.description;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final states = ref.watch(llmModelStatesProvider).value ?? const [];
    final manager = ref.read(llmModelManagerProvider);

    return _EnginePickerDialog(
      title: context.l10n.modelPickerSummaryTitle,
      states: states,
      // Off claims the checkmark: no tier reads as selected while disabled.
      selectedTier: settings.summariesEnabled ? settings.llmTier : null,
      enabledOf: (model) => deviceHasRamGb((model as LlmModel).minRamGb),
      disabledReasonOf: (model) => context.l10n.llmModelNeedsRam(
        (model as LlmModel).sizeLabel,
        model.minRamGb,
      ),
      descriptionOf: (model) => describe(context.l10n, model as LlmModel),
      installedBytes: manager.installedBytes(),
      offLabel: context.l10n.summariesOffOption,
      offDescription: context.l10n.summariesOffDesc,
      offSelected: !settings.summariesEnabled,
      onOff: () =>
          ref.read(settingsRepositoryProvider).setSummariesEnabled(false),
      onSelect: (state) => _select(context, ref, state),
      onDelete: (state) => manager.delete(state.model as LlmModel),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    ModelState<ModelSpec> state,
  ) async {
    final repo = ref.read(settingsRepositoryProvider);
    final manager = ref.read(llmModelManagerProvider);
    if (state.status == ModelStatus.downloading) {
      manager.pause(state.model as LlmModel);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    await repo.setLlmTier(state.model.tier);
    // Choosing a model is also the way back from "No summaries" — re-enable
    // before the drain so parked summary jobs are released with it.
    await repo.setSummariesEnabled(true);
    manager.cancelExcept(state.model.tier);
    await downloadAndDrain(
      messenger,
      ref,
      state,
      download: () => manager.download(state.model as LlmModel),
      readyMessage: l10n.modelReadySummarize(state.model.label),
      failedMessage: l10n.downloadFailed(state.model.label),
    );
  }
}

/// Shared select flow: an installed tier just drains the queue; an absent
/// or paused one downloads (resuming a stashed partial) first (§14
/// model-missing recovery). Selecting a tier cancels any other tier still
/// downloading (§5.6) — the cancelled/paused future stays silent here, only
/// real failures earn the snackbar.
Future<void> downloadAndDrain(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  ModelState<ModelSpec> state, {
  required Future<void> Function() download,
  required String readyMessage,
  required String failedMessage,
}) async {
  final queue = ref.read(jobQueueProvider);

  if (state.status == ModelStatus.ready) {
    await queue.drain();
    return;
  }
  try {
    await download();
    messenger.showSnackBar(SnackBar(content: Text(readyMessage)));
    await queue.drain();
  } on ModelDownloadCancelled {
    // A newer tier choice aborted this one; the new download reports.
  } on ModelDownloadPaused {
    // The user tapped pause; the partial waits on disk for the next tap.
  } on ModelNotificationPermissionDenied {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          messenger.context.l10n.downloadNotificationsPermissionRequired,
        ),
      ),
    );
  } on InsufficientModelStorage {
    messenger.showSnackBar(
      SnackBar(content: Text(messenger.context.l10n.insufficientModelStorage)),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failedMessage)));
  }
}

class _EnginePickerDialog extends ConsumerWidget {
  const _EnginePickerDialog({
    required this.title,
    required this.states,
    required this.selectedTier,
    required this.enabledOf,
    required this.disabledReasonOf,
    required this.installedBytes,
    required this.onSelect,
    required this.onDelete,
    this.descriptionOf,
    this.offLabel,
    this.offDescription,
    this.offSelected = false,
    this.onOff,
  });

  final String title;
  final List<ModelState<ModelSpec>> states;

  /// null → no tier carries the checkmark (summaries switched off).
  final String? selectedTier;
  final bool Function(ModelSpec) enabledOf;
  final String Function(ModelSpec model) disabledReasonOf;
  final int installedBytes;
  final void Function(ModelState<ModelSpec>) onSelect;
  final void Function(ModelState<ModelSpec>) onDelete;

  /// Device-aware copy override; null → the catalog description.
  final String Function(ModelSpec)? descriptionOf;

  /// When [offLabel] is set, an "off" row leads the list (summary picker).
  final String? offLabel;
  final String? offDescription;
  final bool offSelected;
  final VoidCallback? onOff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tape = context.tape;
    // Listed tiers always; unlisted (tiny, tests) only when present.
    final visible = states
        .where((s) => s.model.listed || s.status != ModelStatus.notInstalled)
        .toList();
    final usedMb = (installedBytes / (1024 * 1024)).round();

    return SimpleDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      children: [
        if (offLabel != null)
          _PickerOption(
            label: offLabel!,
            status: '',
            description: offDescription ?? '',
            selected: offSelected,
            enabled: true,
            onSelect: onOff ?? () {},
          ),
        for (final state in visible)
          _PickerOption(
            label: state.model.label,
            status: [
              if (state.failureCode != null) state.failureCode!,
              _statusOf(context, state),
            ].join(' · '),
            description: (descriptionOf ?? (m) => m.description)(state.model),
            selected: selectedTier == state.model.tier,
            enabled: enabledOf(state.model),
            onSelect: () => onSelect(state),
            progress:
                state.status == ModelStatus.downloading ||
                    state.status == ModelStatus.paused
                ? state.progress
                : null,
            // Ready → free the storage; paused → discard the partial.
            onDelete:
                state.status == ModelStatus.ready ||
                    state.status == ModelStatus.paused
                ? () => onDelete(state)
                : null,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
          child: Text(
            context.l10n.storageNote(usedMb),
            style: TextStyle(fontSize: 10, color: tape.ink2),
          ),
        ),
      ],
    );
  }

  String _statusOf(BuildContext context, ModelState<ModelSpec> state) =>
      switch (state.status) {
        ModelStatus.ready => context.l10n.pickerInstalled(
          state.model.sizeLabel,
        ),
        ModelStatus.downloading => context.l10n.pickerDownloading(
          (state.progress * 100).round(),
        ),
        ModelStatus.paused => context.l10n.pickerPaused(
          (state.progress * 100).round(),
        ),
        ModelStatus.notInstalled =>
          enabledOf(state.model)
              ? context.l10n.pickerDownload(state.model.sizeLabel)
              : disabledReasonOf(state.model),
      };
}

/// One picker row: checkmark channel, label, small right-hand status,
/// description line, optional progress bar and delete affordance. Renders
/// model tiers and the summary picker's "No summaries" row alike.
class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.label,
    required this.status,
    required this.description,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    this.progress,
    this.onDelete,
  });

  final String label;
  final String status;
  final String description;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
  final double? progress;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tape = context.tape;

    return InkWell(
      onTap: enabled ? onSelect : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: selected
                        ? Icon(Icons.check, size: 16, color: tape.ink)
                        : null,
                  ),
                  // Wrap, not a bare Row: a long localized status ("paused
                  // at N % — tap to resume") flows onto its own line on
                  // narrow phones instead of crushing the model name into a
                  // one-letter column.
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : null,
                            color: tape.ink,
                          ),
                        ),
                        if (status.isNotEmpty)
                          Text(
                            status,
                            style: TextStyle(fontSize: 10, color: tape.ink2),
                          ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      color: tape.ink2,
                      visualDensity: VisualDensity.compact,
                      tooltip: context.l10n.deleteModelTooltip,
                      onPressed: onDelete,
                    ),
                ],
              ),
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 22, top: 1),
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.4,
                      color: tape.ink2,
                    ),
                  ),
                ),
              if (progress != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 22,
                    top: 6,
                    bottom: 2,
                  ),
                  child: InkProgressBar(fraction: progress!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
