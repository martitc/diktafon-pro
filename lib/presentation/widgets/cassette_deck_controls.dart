import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/tape_colors.dart';
import 'deck.dart';

/// Transport and recording controls on the cassette face. Import stays
/// visible beside the microphone and uses the same tactile deck-key style.
class CassetteDeckControls extends StatelessWidget {
  const CassetteDeckControls({
    super.key,
    required this.playing,
    required this.hasAudio,
    required this.importingAudio,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onImport,
    required this.onRecord,
  });

  final bool playing;
  final bool hasAudio;
  final bool importingAudio;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final VoidCallback onImport;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final tapeColors = context.tape;
    return Container(
      decoration: BoxDecoration(
        color: tapeColors.surface,
        border: Border(top: BorderSide(color: tapeColors.ink, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 340;
            final edgeWidth = compact ? 40.0 : 44.0;
            final gap = compact ? 4.0 : 6.0;
            return Row(
              children: [
                DeckKey(
                  glyph: DeckGlyph.rewind,
                  semanticLabel: context.l10n.back15,
                  width: edgeWidth,
                  onPressed: hasAudio ? onRewind : null,
                ),
                SizedBox(width: gap),
                DeckKey(
                  glyph: playing ? DeckGlyph.pause : DeckGlyph.play,
                  style: DeckKeyStyle.ink,
                  width: compact ? 50 : 56,
                  semanticLabel: playing
                      ? context.l10n.pause
                      : context.l10n.play,
                  onPressed: hasAudio ? onPlayPause : null,
                ),
                SizedBox(width: gap),
                DeckKey(
                  glyph: DeckGlyph.fastForward,
                  semanticLabel: context.l10n.forward15,
                  width: edgeWidth,
                  onPressed: hasAudio ? onForward : null,
                ),
                const Spacer(),
                Tooltip(
                  message: context.l10n.importAudioTooltip,
                  child: DeckKey(
                    glyph: DeckGlyph.importAudio,
                    semanticLabel: importingAudio
                        ? context.l10n.importingAudio
                        : context.l10n.importAudio,
                    width: edgeWidth,
                    onPressed: importingAudio ? null : onImport,
                  ),
                ),
                SizedBox(width: gap),
                DeckKey(
                  glyph: DeckGlyph.record,
                  style: DeckKeyStyle.record,
                  width: edgeWidth,
                  semanticLabel: context.l10n.recordNewMemo,
                  onPressed: onRecord,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
