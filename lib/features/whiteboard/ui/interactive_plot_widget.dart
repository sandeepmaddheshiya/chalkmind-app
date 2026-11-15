import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/plot_model.dart';
import '../recognition/math_function_parser.dart';
import '../rendering/plot_painter.dart';
import '../state/whiteboard_notifier.dart';

class InteractivePlotWidget extends ConsumerStatefulWidget {
  final PlotObject plot;
  final bool isDarkCanvas;

  /// Temporary offset while the plot is part of a selection being dragged.
  final Offset previewOffset;

  const InteractivePlotWidget({
    super.key,
    required this.plot,
    required this.isDarkCanvas,
    this.previewOffset = Offset.zero,
  });

  @override
  ConsumerState<InteractivePlotWidget> createState() =>
      _InteractivePlotWidgetState();
}

class _InteractivePlotWidgetState extends ConsumerState<InteractivePlotWidget> {
  MathFunction? _compiledFunction;
  double _lastScale = 1.0;

  @override
  void initState() {
    super.initState();
    _compile();
  }

  @override
  void didUpdateWidget(covariant InteractivePlotWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plot.equation != widget.plot.equation) {
      _compile();
    }
  }

  void _compile() {
    _compiledFunction = MathFunctionParser.parse(widget.plot.equation);
  }

  void _updatePlot(PlotObject newPlot) {
    ref.read(whiteboardControllerProvider.notifier).updatePlot(newPlot);
  }

  @override
  Widget build(BuildContext context) {
    final plot = widget.plot;
    const toolbarHeight = 42.0;
    const gap = 6.0;

    return Positioned(
      left: plot.rect.left + widget.previewOffset.dx,
      top:
          math.max(0.0, plot.rect.top - toolbarHeight - gap) +
          widget.previewOffset.dy,
      width: plot.rect.width,
      height: plot.rect.height + toolbarHeight + gap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Sleek Floating Frosted-Glass Toolbar Pill
          _buildFloatingToolbar(context),

          const SizedBox(height: gap),

          // 2. Seamless Coordinate Plane Viewport
          Expanded(child: _buildCoordinatePlane(context)),
        ],
      ),
    );
  }

  Widget _buildFloatingToolbar(BuildContext context) {
    final plot = widget.plot;
    final isDark = widget.isDarkCanvas;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xE61E293B)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: isDark ? const Color(0x33FFFFFF) : const Color(0x24000000),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Dedicated Move Handle with clear icon & label
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              final newRect = plot.rect.shift(details.delta);
              _updatePlot(plot.copyWith(rect: newRect));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.open_with_rounded,
                    size: 14,
                    color: isDark ? Colors.white : const Color(0xFF334155),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Move',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Formula indicator with curve color dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF38BDF8) : plot.curveColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _compiledFunction?.cleanFormula ?? plot.equation,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 4),

          // Zoom In (+)
          _buildToolButton(
            icon: Icons.add_rounded,
            tooltip: 'Zoom In Graph',
            onTap: () => _updatePlot(plot.zoom(0.75)),
            isDark: isDark,
          ),

          // Zoom Out (-)
          _buildToolButton(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom Out Graph',
            onTap: () => _updatePlot(plot.zoom(1.33)),
            isDark: isDark,
          ),

          // Reset Origin / View (⛶)
          _buildToolButton(
            icon: Icons.filter_center_focus_rounded,
            tooltip: 'Reset Origin (0,0)',
            onTap: () => _updatePlot(plot.resetView()),
            isDark: isDark,
          ),

          // Toggle Key Points (✦)
          _buildToolButton(
            icon: Icons.auto_awesome_rounded,
            tooltip: 'Toggle Roots & Extrema Badges',
            color: plot.showKeyPoints ? const Color(0xFF2563EB) : null,
            onTap: () =>
                _updatePlot(plot.copyWith(showKeyPoints: !plot.showKeyPoints)),
            isDark: isDark,
          ),

          // Delete (✕)
          _buildToolButton(
            icon: Icons.close_rounded,
            tooltip: 'Remove Graph',
            color: const Color(0xFFEF4444),
            onTap: () {
              ref
                  .read(whiteboardControllerProvider.notifier)
                  .deletePlot(plot.id);
            },
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinatePlane(BuildContext context) {
    final plot = widget.plot;
    final isDark = widget.isDarkCanvas;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0x18FFFFFF)
            : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0x2EFFFFFF) : const Color(0x1F000000),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            // Pan & Pinch Zoom GestureDetector on the coordinate plane
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                _lastScale = 1.0;
              },
              onScaleUpdate: (details) {
                final currentPlot = widget.plot;
                final xSpan = currentPlot.xMax - currentPlot.xMin;
                final ySpan = currentPlot.yMax - currentPlot.yMin;

                // Pinch Zoom
                if ((details.scale - _lastScale).abs() > 0.02) {
                  final factor = _lastScale / details.scale;
                  _lastScale = details.scale;
                  _updatePlot(currentPlot.zoom(factor));
                  return;
                }

                // Coordinate Pan
                if (details.focalPointDelta != Offset.zero) {
                  final dxMath =
                      -(details.focalPointDelta.dx / currentPlot.rect.width) *
                      xSpan;
                  final dyMath =
                      (details.focalPointDelta.dy / currentPlot.rect.height) *
                      ySpan;
                  _updatePlot(currentPlot.pan(dxMath, dyMath));
                }
              },
              child: CustomPaint(
                size: Size.infinite,
                painter: PlotPainter(
                  plot: plot,
                  compiledFunction: _compiledFunction,
                  isDark: isDark,
                ),
              ),
            ),

            // Zoom Range Pill in bottom left corner
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Text(
                  'x: [${plot.xMin.toStringAsFixed(1)}, ${plot.xMax.toStringAsFixed(1)}]',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
              ),
            ),

            // Resize Handle at bottom right
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  final newW = (plot.rect.width + details.delta.dx).clamp(
                    280.0,
                    950.0,
                  );
                  final newH = (plot.rect.height + details.delta.dy).clamp(
                    220.0,
                    800.0,
                  );
                  _updatePlot(
                    plot.copyWith(
                      rect: Rect.fromLTWH(
                        plot.rect.left,
                        plot.rect.top,
                        newW,
                        newH,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.south_east_rounded,
                    size: 16,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool isDark,
    Color? color,
  }) {
    final iconColor =
        color ?? (isDark ? Colors.white70 : const Color(0xFF475569));
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.transparent,
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}
