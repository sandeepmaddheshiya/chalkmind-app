import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tool_type.dart';
import '../state/whiteboard_notifier.dart';

class WhiteboardToolbar extends ConsumerWidget {
  final VoidCallback onToggleProperties;
  final bool isPropertiesOpen;
  final VoidCallback? onHideToolbar;
  final GestureDragUpdateCallback? onPanUpdate;

  const WhiteboardToolbar({
    super.key,
    required this.onToggleProperties,
    required this.isPropertiesOpen,
    this.onHideToolbar,
    this.onPanUpdate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tools = [
      (ToolType.pen, Icons.edit_rounded, 'Pen (P)'),
      (ToolType.pencil, Icons.mode_edit_outline_rounded, 'Pencil'),
      (ToolType.marker, Icons.brush_rounded, 'Marker (M)'),
      (ToolType.highlighter, Icons.border_color_rounded, 'Highlighter (H)'),
      (ToolType.strokeEraser, Icons.auto_fix_normal_rounded, 'Eraser (E)'),
      (ToolType.shape, Icons.category_rounded, 'Shapes (S)'),
      (ToolType.text, Icons.title_rounded, 'Text (T)'),
      (ToolType.select, Icons.highlight_alt_rounded, 'Select (V)'),
      (ToolType.laser, Icons.flare_rounded, 'Laser (L)'),
      (ToolType.hand, Icons.pan_tool_rounded, 'Pan Canvas (Space)'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle to place toolbar anywhere
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: onPanUpdate,
            child: Tooltip(
              message: 'Drag to move toolbar anywhere',
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                ),
              ),
            ),
          ),
          // Active Color & Properties trigger
          GestureDetector(
            onTap: onToggleProperties,
            child: Tooltip(
              message: 'Color & Tool Settings',
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isPropertiesOpen
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: state.selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 24,
            height: 1,
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
          const SizedBox(height: 6),

          // Tool buttons
          for (final item in tools) ...[
            if (item.$1 == ToolType.strokeEraser)
              // One eraser button: tap again to switch whole-stroke <-> partial.
              _ToolIconButton(
                icon: state.currentTool == ToolType.areaEraser
                    ? Icons.cleaning_services_rounded
                    : item.$2,
                tooltip: state.currentTool == ToolType.areaEraser
                    ? 'Partial Eraser (E) - erases only ink under the cursor. Tap to switch to whole-stroke.'
                    : state.currentTool == ToolType.strokeEraser
                    ? 'Stroke Eraser (E) - removes whole strokes. Tap to switch to partial.'
                    : 'Eraser (E)',
                isSelected: state.currentTool.isEraser,
                onPressed: () {
                  final n = ref.read(whiteboardControllerProvider.notifier);
                  if (state.currentTool == ToolType.strokeEraser) {
                    n.setTool(ToolType.areaEraser);
                  } else if (state.currentTool == ToolType.areaEraser) {
                    n.setTool(ToolType.strokeEraser);
                  } else {
                    n.setTool(ToolType.strokeEraser);
                  }
                },
              )
            else
              _ToolIconButton(
                icon: item.$2,
                tooltip: item.$3,
                isSelected: state.currentTool == item.$1,
                presetColor: state.toolPresets[item.$1]?.color,
                onPressed: () {
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .setTool(item.$1);
                },
              ),
            const SizedBox(height: 4),
          ],

          const SizedBox(height: 4),
          Container(
            width: 24,
            height: 1,
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
          const SizedBox(height: 6),

          // Left/Right Handed Dock Toggle
          IconButton(
            icon: Icon(
              state.isLeftHanded ? Icons.dock_rounded : Icons.dock_outlined,
              size: 19,
            ),
            tooltip: state.isLeftHanded
                ? 'Switch to Right-Handed'
                : 'Switch to Left-Handed',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              ref
                  .read(whiteboardControllerProvider.notifier)
                  .toggleLeftHanded();
            },
          ),

          // Hide / Minimize Toolbar Button
          if (onHideToolbar != null)
            IconButton(
              icon: Icon(
                Icons.visibility_off_outlined,
                size: 18,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
              tooltip: 'Hide Toolbar',
              visualDensity: VisualDensity.compact,
              onPressed: onHideToolbar,
            ),
        ],
      ),
    );
  }
}

class _ToolIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final Color? presetColor;
  final VoidCallback onPressed;

  const _ToolIconButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    this.presetColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isSelected
            ? primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: primary, width: 1.5)
                  : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    icon,
                    size: 22,
                    color: isSelected ? primary : Colors.grey.shade600,
                  ),
                ),
                if (presetColor != null)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: presetColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF1F2937)
                              : Colors.white,
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
