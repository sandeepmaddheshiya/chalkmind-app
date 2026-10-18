import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/background_style.dart';
import '../models/tool_type.dart';
import '../state/whiteboard_notifier.dart';
import '../state/whiteboard_state.dart';

class ToolPropertiesPanel extends ConsumerWidget {
  const ToolPropertiesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Color Palette
          const Text(
            'Color',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: WhiteboardState.standardPalette.map((colorVal) {
              final isSelected = state.selectedColorValue == colorVal;
              return GestureDetector(
                onTap: () {
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .setColor(colorVal);
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(colorVal),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : (colorVal == 0xFFFFFFFF
                              ? Colors.grey.shade400
                              : Colors.transparent),
                      width: isSelected ? 3 : 1,
                    ),
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                    ],
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: Color(colorVal).computeLuminance() > 0.5
                              ? Colors.black87
                              : Colors.white,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
          const Divider(height: 24),

          // Section 2: Stroke Width / Size Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Stroke Width',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                '${state.selectedStrokeWidth.toStringAsFixed(1)} pt',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: state.selectedStrokeWidth,
                  min: 1.0,
                  max: 36.0,
                  divisions: 35,
                  onChanged: (val) {
                    ref
                        .read(whiteboardControllerProvider.notifier)
                        .setStrokeWidth(val);
                  },
                ),
              ),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
                child: Container(
                  width: state.selectedStrokeWidth.clamp(2.0, 24.0),
                  height: state.selectedStrokeWidth.clamp(2.0, 24.0),
                  decoration: BoxDecoration(
                    color: state.selectedColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),

          // Section 3: Shapes Specific Options
          if (state.currentTool == ToolType.shape) ...[
            const Divider(height: 24),
            const Text(
              'Shape Type',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: ShapeType.values.map((st) {
                final isSelected = state.selectedShapeType == st;
                return ChoiceChip(
                  label: Text(st.displayName, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      ref
                          .read(whiteboardControllerProvider.notifier)
                          .setShapeType(st);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fill Shape', style: TextStyle(fontSize: 13)),
                Switch(
                  value: state.isShapeFilled,
                  onChanged: (val) {
                    ref
                        .read(whiteboardControllerProvider.notifier)
                        .toggleShapeFilled();
                  },
                ),
              ],
            ),
          ],

          // Section 4: Canvas Background Options
          const Divider(height: 24),
          const Text(
            'Canvas Background',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: BackgroundStyle.values.map((style) {
                final currentBg = state.project.currentPage.background;
                final isSelected = currentBg.style == style;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(style.displayName,
                        style: const TextStyle(fontSize: 11)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        ref
                            .read(whiteboardControllerProvider.notifier)
                            .setBackground(currentBg.copyWith(style: style));
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: CanvasBackground.presetColors.map((colorVal) {
              final currentBg = state.project.currentPage.background;
              final isSelected = currentBg.colorValue == colorVal;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    ref
                        .read(whiteboardControllerProvider.notifier)
                        .setBackground(currentBg.copyWith(colorValue: colorVal));
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(colorVal),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade400,
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 14,
                            color: Color(colorVal).computeLuminance() > 0.5
                                ? Colors.black87
                                : Colors.white,
                          )
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),

          const Divider(height: 24),

          // Section 5: AI & Smart Recognition Toggles
          const Text(
            'Smart Assistant & Recognition',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),

          // Auto Shape Toggle
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.interests_outlined, size: 20),
            title: const Text('Auto Shape Detection', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            subtitle: const Text('Convert hand-drawn strokes to geometric shapes', style: TextStyle(fontSize: 10)),
            value: state.isAutoShapeEnabled,
            onChanged: (val) {
              ref.read(whiteboardControllerProvider.notifier).setAutoShape(val);
            },
          ),

          // Auto Math Solver Toggle
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.auto_awesome_rounded, size: 20, color: Color(0xFF059669)),
            title: const Text('Auto Math Solver', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            subtitle: const Text('Automatically solve equations ending in "="', style: TextStyle(fontSize: 10)),
            value: state.isAutoMathEnabled,
            onChanged: (val) {
              ref.read(whiteboardControllerProvider.notifier).setAutoMath(val);
            },
          ),

          // Solve Selected Math Button (if objects are selected)
          if (state.selectedObjectIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.psychology_outlined, size: 18),
                label: Text(
                  'Solve Selected (${state.selectedObjectIds.length})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  ref.read(whiteboardControllerProvider.notifier).solveSelectedStrokes();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
