import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tool_type.dart';
import '../state/whiteboard_notifier.dart';

enum CanvasZoomAction {
  none,
  zoomIn,
  zoomOut,
  reset,
  fitContent,
  panLeft,
  panRight,
  panUp,
  panDown,
}

class CanvasZoomActionNotifier extends Notifier<CanvasZoomAction> {
  @override
  CanvasZoomAction build() => CanvasZoomAction.none;

  void trigger(CanvasZoomAction action) {
    state = action;
  }

  void reset() {
    state = CanvasZoomAction.none;
  }
}

final canvasZoomActionProvider =
    NotifierProvider<CanvasZoomActionNotifier, CanvasZoomAction>(
      () => CanvasZoomActionNotifier(),
    );

/// Floating zoom & pan controls for the whiteboard canvas (especially useful in Infinite Canvas mode)
class CanvasZoomControls extends ConsumerWidget {
  const CanvasZoomControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final zoomPercent = (state.zoomScale * 100).round();

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      color: isDark ? const Color(0xFF1F2937) : Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zoom Out Button
            IconButton(
              icon: const Icon(Icons.remove_rounded, size: 18),
              tooltip: 'Zoom Out',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                ref
                    .read(canvasZoomActionProvider.notifier)
                    .trigger(CanvasZoomAction.zoomOut);
              },
            ),

            // Zoom Percentage Chip / Reset Trigger
            GestureDetector(
              onTap: () {
                ref
                    .read(canvasZoomActionProvider.notifier)
                    .trigger(CanvasZoomAction.reset);
              },
              child: Tooltip(
                message: 'Reset Zoom (100%)',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$zoomPercent%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            // Zoom In Button
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 18),
              tooltip: 'Zoom In',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                ref
                    .read(canvasZoomActionProvider.notifier)
                    .trigger(CanvasZoomAction.zoomIn);
              },
            ),

            // Canvas Mode Icon Indicator
            Tooltip(
              message: state.isInfiniteCanvas
                  ? 'Infinite Canvas Mode'
                  : 'Paginated Sheet Mode',
              child: Padding(
                padding: const EdgeInsets.only(left: 2, right: 6),
                child: Icon(
                  state.isInfiniteCanvas
                      ? Icons.all_inclusive_rounded
                      : Icons.auto_stories_rounded,
                  size: 16,
                  color: state.isInfiniteCanvas
                      ? const Color(0xFF059669)
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
              ),
            ),

            Container(
              width: 1,
              height: 18,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              margin: const EdgeInsets.symmetric(horizontal: 2),
            ),

            // Hand / Pan Tool Toggle Button (Move Infinite Canvas with 1 finger)
            IconButton(
              icon: Icon(
                Icons.pan_tool_rounded,
                size: 17,
                color: state.currentTool == ToolType.hand
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
              style: IconButton.styleFrom(
                backgroundColor: state.currentTool == ToolType.hand
                    ? const Color(0xFF6366F1)
                    : Colors.transparent,
                shape: const CircleBorder(),
              ),
              tooltip: state.currentTool == ToolType.hand
                  ? 'Pan Tool Active (Drag canvas with 1 finger)'
                  : 'Pan Tool (Move canvas with 1 finger)',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (state.currentTool == ToolType.hand) {
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .setTool(ToolType.pen);
                } else {
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .setTool(ToolType.hand);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
