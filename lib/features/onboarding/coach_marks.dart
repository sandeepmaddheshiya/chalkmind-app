import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One step of a spotlight tutorial. With no [target] (or a target that is
/// not currently on screen... see [CoachMarkTour]) the card is centred.
class CoachStep {
  final GlobalKey? target;
  final IconData icon;
  final String title;
  final String body;

  /// When true and the target isn't on screen, the step is skipped rather
  /// than shown centred (e.g. a toolbar the user has hidden).
  final bool skipIfMissing;

  const CoachStep({
    this.target,
    required this.icon,
    required this.title,
    required this.body,
    this.skipIfMissing = true,
  });
}

/// Step-by-step spotlight tutorial over the real UI: everything is dimmed
/// except the control being explained, with a short card beside it.
class CoachMarkTour {
  /// Shows the tour. Completes with true if the user finished it, false if
  /// they skipped. Steps whose targets aren't visible are left out.
  static Future<bool> show(BuildContext context, List<CoachStep> steps) {
    final visible = [
      for (final s in steps)
        if (s.target == null || _rectOf(s.target!) != null || !s.skipIfMissing)
          s,
    ];
    if (visible.isEmpty) return Future.value(true);
    final overlay = Overlay.of(context, rootOverlay: true);
    final done = Completer<bool>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CoachMarkOverlay(
        steps: visible,
        onClose: (completed) {
          entry.remove();
          if (!done.isCompleted) done.complete(completed);
        },
      ),
    );
    overlay.insert(entry);
    return done.future;
  }

  /// Global rect of a mounted, laid-out, non-empty widget; null otherwise.
  static Rect? _rectOf(GlobalKey key) {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize || ro.size.isEmpty) {
      return null;
    }
    return ro.localToGlobal(Offset.zero) & ro.size;
  }
}

class _CoachMarkOverlay extends StatefulWidget {
  final List<CoachStep> steps;
  final void Function(bool completed) onClose;
  const _CoachMarkOverlay({required this.steps, required this.onClose});

  @override
  State<_CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<_CoachMarkOverlay> {
  int _i = 0;

  CoachStep get _step => widget.steps[_i];
  bool get _isLast => _i == widget.steps.length - 1;

  void _next() => _isLast ? widget.onClose(true) : setState(() => _i++);
  void _back() {
    if (_i > 0) setState(() => _i--);
  }

  void _skip() => widget.onClose(false);

  /// Target rect in this overlay's coordinates.
  Rect? _holeFor(CoachStep s) {
    if (s.target == null) return null;
    final global = CoachMarkTour._rectOf(s.target!);
    final me = context.findRenderObject();
    if (global == null || me is! RenderBox || !me.hasSize) return global;
    final topLeft = me.globalToLocal(global.topLeft);
    return topLeft & global.size;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context); // rebuild on rotation/resize
    final padding = MediaQuery.paddingOf(context);
    // Compute after layout so targets have settled positions.
    final hole = _holeFor(_step)?.inflate(6);
    final theme = Theme.of(context);

    return Material(
      type: MaterialType.transparency,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
          const SingleActivator(LogicalKeyboardKey.enter): _next,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _back,
          const SingleActivator(LogicalKeyboardKey.escape): _skip,
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              // Dim everything except the spotlight; absorb taps so the
              // board isn't edited by accident during the tour.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: hole == null
                      // No target (intro / closing card): plain dim.
                      ? CustomPaint(
                          painter: _ScrimPainter(
                            hole: null,
                            color: Colors.black.withValues(alpha: 0.62),
                          ),
                        )
                      : TweenAnimationBuilder<Rect?>(
                          tween: RectTween(end: hole),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          builder: (_, r, _) => CustomPaint(
                            painter: _ScrimPainter(
                              hole: r,
                              color: Colors.black.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                ),
              ),
              _positionedCard(screen, padding, hole, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _positionedCard(
    Size screen,
    EdgeInsets padding,
    Rect? hole,
    ThemeData theme,
  ) {
    final cardWidth = math.min(360.0, screen.width - 32);
    final card = _Card(
      step: _step,
      index: _i,
      total: widget.steps.length,
      isLast: _isLast,
      onNext: _next,
      onBack: _i > 0 ? _back : null,
      onSkip: _skip,
      width: cardWidth,
    );
    if (hole == null) {
      return Center(child: card);
    }
    // Prefer below the target, then above, then beside it.
    const gap = 14.0;
    const estimatedHeight = 230.0;
    final spaceBelow = screen.height - padding.bottom - hole.bottom;
    final spaceAbove = hole.top - padding.top;
    final left = (hole.center.dx - cardWidth / 2).clamp(
      16.0,
      screen.width - cardWidth - 16,
    );
    if (spaceBelow >= estimatedHeight + gap) {
      return Positioned(left: left, top: hole.bottom + gap, child: card);
    }
    if (spaceAbove >= estimatedHeight + gap) {
      return Positioned(
        left: left,
        bottom: screen.height - hole.top + gap,
        child: card,
      );
    }
    // Tall target (e.g. vertical toolbar): place to the side with more room.
    final rightRoom = screen.width - hole.right;
    final sideLeft = rightRoom >= cardWidth + gap + 16
        ? hole.right + gap
        : math.max(16.0, hole.left - gap - cardWidth);
    final top = (hole.center.dy - estimatedHeight / 2).clamp(
      padding.top + 16,
      screen.height - estimatedHeight - 16,
    );
    return Positioned(left: sideLeft, top: top, child: card);
  }
}

class _Card extends StatelessWidget {
  final CoachStep step;
  final int index;
  final int total;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;
  final double width;

  const _Card({
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Semantics(
      container: true,
      label: 'Tutorial step ${index + 1} of $total',
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface,
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(step.icon, size: 18, color: primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${index + 1}/$total',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  step.body,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: (index + 1) / total,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 4),
                // Wraps onto two lines instead of overflowing with large text.
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 4,
                  children: [
                    if (!isLast)
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onSkip,
                        child: const Text('Skip'),
                      ),
                    if (onBack != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onBack,
                        child: const Text('Back'),
                      ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onNext,
                      child: Text(isLast ? 'Done' : 'Next'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dims the screen with a rounded "spotlight" hole and a soft ring.
class _ScrimPainter extends CustomPainter {
  final Rect? hole;
  final Color color;
  const _ScrimPainter({required this.hole, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(screen, Paint()..color = color);
      return;
    }
    final rr = RRect.fromRectAndRadius(hole!, const Radius.circular(12));
    final dimmed = Path.combine(
      PathOperation.difference,
      screen,
      Path()..addRRect(rr),
    );
    canvas.drawPath(dimmed, Paint()..color = color);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) =>
      old.hole != hole || old.color != color;
}
