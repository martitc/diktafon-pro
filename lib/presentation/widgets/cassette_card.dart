import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../data/repositories/cassette_repository.dart';
import '../../domain/palette.dart';
import '../../l10n/l10n.dart';
import '../theme/theme.dart';
import 'pixel_tape.dart';

/// A cassette tile (§5.2, mockups r10/r11): the app icon's pixel art scaled
/// nearest-neighbour, palette-swapped to the tape's accent, the name printed
/// on the cream label band and "N memos · last record" on the colour strip.
/// The label inks are fixed — the tile is a physical object and doesn't
/// follow the theme — only the shell ink lifts one step in dark theme so
/// the silhouette reads on dark paper (r11).
class CassetteCard extends StatelessWidget {
  const CassetteCard({
    super.key,
    required this.overview,
    this.readyCount = 0,
    this.isProcessing = false,
    this.hasFailure = false,
    this.onTap,
    this.onLongPress,
  });

  final CassetteOverview overview;
  final int readyCount;
  final bool isProcessing;
  final bool hasFailure;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cassette = overview.cassette;
    final label = cassette.label;
    final l10n = context.l10n;
    // The accent arrives with the name (D10): warm grey until then.
    final hue = cassette.titleIsUserSet || label != null
        ? cassetteHueIndex(cassette.colorSeed)
        : null;
    return Semantics(
      button: true,
      label: l10n.cardSemantics(
        label ?? l10n.untitledCassette,
        '${l10n.memoCount(overview.memoCount)}, ${l10n.cassetteReadyCount(readyCount.clamp(0, overview.memoCount), overview.memoCount)}',
      ),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final spriteHeight = w * tapeSpriteHeight / tapeSpriteWidth;
            final h = spriteHeight;
            // The mockup's type scale: 14 px Jersey 10 name / 7 px mono meta
            // on a 157 px tile (the 2-up portrait-phone width).
            final scale = w / 157.0;
            final allReady =
                overview.memoCount > 0 && readyCount >= overview.memoCount;
            return Column(
              children: [
                SizedBox(
                  width: w,
                  height: spriteHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _TapeSprite(
                        hue: hue,
                        windingWidth: tapeWindingWidth(_fullness()),
                        dark: Theme.of(context).brightness == Brightness.dark,
                      ),
                      if (isProcessing)
                        const Positioned.fill(child: _SpinningReels()),
                      _print(
                        tapeNameBand,
                        w,
                        h,
                        label != null
                            ? Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontFamily: displayFont,
                                  fontFamilyFallback: fontFallback,
                                  fontSize: 14 * scale,
                                  height: 1,
                                  color: tapeNameInk,
                                ),
                              )
                            : Text(
                                l10n.untitledCassette,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontFamily: bodyFont,
                                  fontFamilyFallback: fontFallback,
                                  fontSize: 8 * scale,
                                  height: 1,
                                  fontStyle: FontStyle.italic,
                                  color: tapePlaceholderInk,
                                ),
                              ),
                      ),
                      _print(
                        tapeMetaStrip,
                        w,
                        h,
                        Text(
                          _metaLine(context),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontFamily: bodyFont,
                            fontFamilyFallback: fontFallback,
                            fontSize: 7 * scale,
                            height: 1,
                            color: tapeNameInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (overview.memoCount > 0) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.cassetteReadyCount(
                            readyCount.clamp(0, overview.memoCount),
                            overview.memoCount,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: bodyFont,
                            fontFamilyFallback: fontFallback,
                            fontSize: 9 * scale,
                            color: allReady
                                ? const Color(0xFF287B51)
                                : hasFailure
                                ? const Color(0xFFB34D40)
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (allReady)
                        const Icon(
                          Icons.check_circle,
                          size: 13,
                          color: Color(0xFF287B51),
                        )
                      else if (hasFailure)
                        const Icon(
                          Icons.error_outline,
                          size: 13,
                          color: Color(0xFFB34D40),
                        )
                      else if (isProcessing)
                        Icon(
                          Icons.sync,
                          size: 13,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: allReady ? 1 : (isProcessing ? null : 0),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        allReady
                            ? const Color(0xFF3A9868)
                            : hasFailure
                            ? const Color(0xFFB34D40)
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Centers [text] on a sprite-space band (fractions of the tile).
  Widget _print(Rect band, double w, double h, Widget text) => Positioned(
    left: band.left * w,
    top: band.top * h,
    width: band.width * w,
    height: band.height * h,
    child: Center(child: text),
  );

  String _metaLine(BuildContext context) {
    final l10n = context.l10n;
    final count = overview.memoCount;
    if (count == 0) return l10n.cardEmptyMeta;
    final memoPart = l10n.memoCount(count);
    if (overview.cassette.label == null) {
      return l10n.cardMetaNaming(memoPart);
    }
    return l10n.cardMetaUpdated(
      memoPart,
      relativeDate(context, overview.cassette.updatedAt),
    );
  }

  /// 0..1 → wound-tape block width; a glanceable fullness cue (§5.2).
  /// Saturates at one hour of tape.
  double _fullness() =>
      (overview.totalDurationMs / Duration.millisecondsPerHour).clamp(0.0, 1.0);
}

/// Small reel hubs rotate only while work is active. The underlying cassette
/// remains pixel art; three light perforations make motion visible at tile size.
class _SpinningReels extends StatefulWidget {
  const _SpinningReels();

  @override
  State<_SpinningReels> createState() => _SpinningReelsState();
}

class _SpinningReelsState extends State<_SpinningReels>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => CustomPaint(
      painter: _ReelPainter(_controller.value * 2 * 3.141592653589793),
    ),
  );
}

class _ReelPainter extends CustomPainter {
  const _ReelPainter(this.rotation);

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFE2D8C5);
    for (final x in [0.298, 0.702]) {
      final center = Offset(size.width * x, size.height * 0.475);
      for (var i = 0; i < 3; i++) {
        final angle = rotation + i * 2 * 3.141592653589793 / 3;
        final dot = center + Offset.fromDirection(angle, size.width * 0.047);
        canvas.drawCircle(dot, size.width * 0.018, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ReelPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}

/// "today 14:02" / "yesterday" / "28 Jun" — the grid meta format (mockup 02).
String relativeDate(BuildContext context, DateTime t) {
  final locale = Localizations.localeOf(context).toString();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) {
    return context.l10n.todayAt(DateFormat.Hm(locale).format(t));
  }
  if (day == today.subtract(const Duration(days: 1))) {
    return context.l10n.yesterday;
  }
  if (t.year == now.year) return DateFormat('d MMM', locale).format(t);
  return DateFormat('d MMM yyyy', locale).format(t);
}

/// Resolves the composed sprite variant and paints it with no smoothing —
/// pixels enlarge, nothing else (§5.2).
class _TapeSprite extends StatefulWidget {
  const _TapeSprite({
    required this.hue,
    required this.windingWidth,
    required this.dark,
  });

  final int? hue;
  final int windingWidth;
  final bool dark;

  @override
  State<_TapeSprite> createState() => _TapeSpriteState();
}

class _TapeSpriteState extends State<_TapeSprite> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_TapeSprite old) {
    super.didUpdateWidget(old);
    if (old.hue != widget.hue ||
        old.windingWidth != widget.windingWidth ||
        old.dark != widget.dark) {
      _resolve();
    }
  }

  void _resolve() {
    final hue = widget.hue;
    final windingWidth = widget.windingWidth;
    final dark = widget.dark;
    tapeSpriteImage(hue: hue, windingWidth: windingWidth, dark: dark).then((
      image,
    ) {
      // A stale resolve (variant changed while composing) must not win.
      if (mounted &&
          hue == widget.hue &&
          windingWidth == widget.windingWidth &&
          dark == widget.dark) {
        setState(() => _image = image);
      }
    });
  }

  @override
  Widget build(BuildContext context) => RawImage(
    image: _image,
    fit: BoxFit.fill,
    filterQuality: FilterQuality.none,
  );
}
