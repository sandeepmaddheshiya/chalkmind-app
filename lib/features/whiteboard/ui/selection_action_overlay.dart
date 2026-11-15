import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tool_type.dart';
import '../state/whiteboard_notifier.dart';

/// Floating context action bar shown when objects are selected using the Selector tool.
/// Provides 1-tap "Solve Selected", "Delete", and "Clear Selection" directly on the canvas.
class SelectionActionOverlay extends ConsumerWidget {
  const SelectionActionOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);

    // Only visible when selector tool is active and at least one object is selected
    final isVisible =
        state.currentTool == ToolType.select &&
        state.selectedObjectIds.isNotEmpty;

    if (!isVisible) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCount = state.selectedObjectIds.length;
    final isCalculating = state.isCalculatingMath;

    return Center(
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(30),
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Selection Counter Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.highlight_alt_rounded,
                      size: 15,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$selectedCount selected',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 22,
                color: isDark ? Colors.white24 : Colors.grey.shade300,
              ),
              const SizedBox(width: 8),

              // Solve Selected Button
              if (isCalculating) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF059669),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Solving...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 34),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text(
                    'Solve Selected',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    ref
                        .read(whiteboardControllerProvider.notifier)
                        .solveSelectedStrokes();
                  },
                ),
              ],

              const SizedBox(width: 6),

              // Delete Selected Button
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                tooltip: 'Delete Selected',
                visualDensity: VisualDensity.compact,
                color: isDark ? Colors.red.shade300 : Colors.red.shade600,
                onPressed: () {
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .deleteSelected();
                },
              ),

              // Clear Selection Button
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Clear Selection',
                visualDensity: VisualDensity.compact,
                color: isDark ? Colors.white60 : Colors.black54,
                onPressed: () {
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .clearSelection();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
