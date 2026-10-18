import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tool_type.dart';
import '../state/whiteboard_notifier.dart';

class WhiteboardToolbar extends ConsumerWidget {
  final VoidCallback onToggleProperties;
  final bool isPropertiesOpen;

  const WhiteboardToolbar({
    super.key,
    required this.onToggleProperties,
    required this.isPropertiesOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tools = [
      (ToolType.pen, Icons.edit_rounded, 'Pen'),
      (ToolType.pencil, Icons.mode_edit_outline_rounded, 'Pencil'),
      (ToolType.marker, Icons.brush_rounded, 'Marker'),
      (ToolType.highlighter, Icons.border_color_rounded, 'Highlighter'),
      (ToolType.strokeEraser, Icons.auto_fix_normal_rounded, 'Eraser'),
      (ToolType.shape, Icons.category_rounded, 'Shapes'),
      (ToolType.text, Icons.title_rounded, 'Text'),
      (ToolType.select, Icons.highlight_alt_rounded, 'Select'),
      (ToolType.laser, Icons.flare_rounded, 'Laser'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
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
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
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
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
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
              state.isLeftHanded
                  ? Icons.dock_rounded
                  : Icons.dock_outlined,
              size: 20,
            ),
            tooltip: state.isLeftHanded
                ? 'Switch to Right-Handed'
                : 'Switch to Left-Handed',
            onPressed: () {
              ref
                  .read(whiteboardControllerProvider.notifier)
                  .toggleLeftHanded();
            },
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
        color: isSelected ? primary.withValues(alpha: 0.15) : Colors.transparent,
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
                          color: isDark ? const Color(0xFF1F2937) : Colors.white,
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
