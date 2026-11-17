import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tool_type.dart';
import '../state/whiteboard_notifier.dart';
import 'canvas_zoom_controls.dart';

/// Single, unified, ultra-sleek bottom bar combining:
/// 1. Page / Board Navigation & Management
/// 2. Canvas Zoom In / Out / Reset
/// 3. Hand / Pan Tool Toggle
/// 4. Canvas Mode (Infinite / Paginated)
/// 5. Selection Actions (Solve, Delete, Clear)
class UnifiedBottomBar extends ConsumerWidget {
  const UnifiedBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final currentPageIndex = state.project.currentPageIndex;
    final totalPages = state.project.totalPages;
    final isInfinite = state.isInfiniteCanvas;
    final itemNoun = isInfinite ? 'Board' : 'Page';
    final zoomPercent = state.zoomPercent;
    final hasSelection = state.selectedObjectIds.isNotEmpty;

    return Center(
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(30),
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Selection Quick Actions if elements are selected
                if (hasSelection) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF374151)
                          : const Color(0xFFEEF2F6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.highlight_alt_rounded,
                          size: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${state.selectedObjectIds.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),

                  // Solve Selected Button
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF059669),
                    ),
                    icon: state.isCalculatingMath
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF059669),
                              ),
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded, size: 15),
                    label: Text(
                      state.isCalculatingMath ? 'Solving...' : 'Solve',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: state.isCalculatingMath
                        ? null
                        : () {
                            ref
                                .read(whiteboardControllerProvider.notifier)
                                .solveSelectedStrokes();
                          },
                  ),

                  // Duplicate Selected Button
                  IconButton(
                    icon: const Icon(Icons.copy_all_rounded, size: 17),
                    tooltip: 'Duplicate (Ctrl+D)',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref
                          .read(whiteboardControllerProvider.notifier)
                          .duplicateSelected();
                    },
                  ),

                  // Delete Selected Button
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                      size: 18,
                    ),
                    tooltip: 'Delete Selected (Del)',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref
                          .read(whiteboardControllerProvider.notifier)
                          .deleteSelected();
                    },
                  ),

                  // Clear Selection Button
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    tooltip: 'Clear Selection',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref
                          .read(whiteboardControllerProvider.notifier)
                          .setSelectedObjects({});
                    },
                  ),

                  _buildDivider(isDark),
                ],

                // 1. Page/Board Navigation
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  tooltip: 'Previous $itemNoun',
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPageIndex > 0
                      ? () {
                          ref
                              .read(whiteboardControllerProvider.notifier)
                              .previousPage();
                        }
                      : null,
                ),

                // Page / Board Counter Chip (Tap for overview sheet)
                GestureDetector(
                  onTap: () => _showPageOverviewSheet(context, ref),
                  child: Tooltip(
                    message: 'View all ${itemNoun}s',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isInfinite
                                ? Icons.all_inclusive_rounded
                                : Icons.auto_stories_rounded,
                            size: 13,
                            color: isInfinite
                                ? const Color(0xFF10B981)
                                : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$itemNoun ${currentPageIndex + 1}/$totalPages',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  tooltip: 'Next $itemNoun',
                  visualDensity: VisualDensity.compact,
                  onPressed: currentPageIndex < totalPages - 1
                      ? () {
                          ref
                              .read(whiteboardControllerProvider.notifier)
                              .nextPage();
                        }
                      : null,
                ),

                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  tooltip: 'Add $itemNoun',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    ref
                        .read(whiteboardControllerProvider.notifier)
                        .addNewPage();
                  },
                ),

                _buildDivider(isDark),

                // 2. Canvas Zoom Controls
                IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 16),
                  tooltip: 'Zoom Out',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    ref
                        .read(canvasZoomActionProvider.notifier)
                        .trigger(CanvasZoomAction.zoomOut);
                  },
                ),

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
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
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

                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  tooltip: 'Zoom In (Ctrl +)',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    ref
                        .read(canvasZoomActionProvider.notifier)
                        .trigger(CanvasZoomAction.zoomIn);
                  },
                ),

                IconButton(
                  icon: const Icon(Icons.fit_screen_rounded, size: 16),
                  tooltip: 'Fit All Content (Shift+1)',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    ref
                        .read(canvasZoomActionProvider.notifier)
                        .trigger(CanvasZoomAction.fitContent);
                  },
                ),

                _buildDivider(isDark),

                // 3. Hand / Pan Canvas Tool
                IconButton(
                  icon: Icon(
                    Icons.pan_tool_rounded,
                    size: 16,
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
                      ? 'Pan Active (Drag canvas with 1 finger)'
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

                _buildDivider(isDark),

                // 4. More Options Popup
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  tooltip: 'Board & Canvas Options',
                  padding: EdgeInsets.zero,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'mode',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isInfinite
                              ? Icons.auto_stories_rounded
                              : Icons.all_inclusive_rounded,
                          size: 18,
                          color: const Color(0xFF6366F1),
                        ),
                        title: Text(
                          isInfinite
                              ? 'Switch to Paginated Sheets'
                              : 'Switch to Infinite Canvas',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'duplicate',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.content_copy_rounded,
                          size: 18,
                        ),
                        title: Text(
                          'Duplicate $itemNoun',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'overview',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.grid_view_rounded, size: 18),
                        title: Text(
                          '$itemNoun Grid Overview',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'clear',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.clear_all_rounded,
                          size: 18,
                          color: Colors.red,
                        ),
                        title: Text(
                          'Clear $itemNoun Content',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ],
                  onSelected: (val) {
                    if (val == 'mode') {
                      ref
                          .read(whiteboardControllerProvider.notifier)
                          .setInfiniteCanvas(!isInfinite);
                    } else if (val == 'duplicate') {
                      ref
                          .read(whiteboardControllerProvider.notifier)
                          .duplicateCurrentPage();
                    } else if (val == 'overview') {
                      _showPageOverviewSheet(context, ref);
                    } else if (val == 'clear') {
                      _confirmClearPage(context, ref, itemNoun);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      width: 1,
      height: 18,
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
      margin: const EdgeInsets.symmetric(horizontal: 3),
    );
  }

  void _confirmClearPage(BuildContext context, WidgetRef ref, String itemNoun) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear $itemNoun?'),
        content: Text(
          'This will erase all handwritten ink, shapes, and text on this $itemNoun. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref
                  .read(whiteboardControllerProvider.notifier)
                  .clearCurrentPage();
              Navigator.pop(ctx);
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _showPageOverviewSheet(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(whiteboardControllerProvider);
            final project = state.project;
            final itemNoun = state.isInfiniteCanvas ? 'Board' : 'Page';

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${project.totalPages} ${itemNoun}s',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () {
                            ref
                                .read(whiteboardControllerProvider.notifier)
                                .addNewPage();
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text('New $itemNoun'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      scrollDirection: Axis.horizontal,
                      itemCount: project.pages.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        final isCurrent = index == project.currentPageIndex;
                        final page = project.pages[index];

                        return GestureDetector(
                          onTap: () {
                            ref
                                .read(whiteboardControllerProvider.notifier)
                                .selectPage(index);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            width: 130,
                            decoration: BoxDecoration(
                              color: page.background.color,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCurrent
                                    ? Theme.of(context).colorScheme.primary
                                    : (isDark
                                          ? Colors.grey.shade700
                                          : Colors.grey.shade300),
                                width: isCurrent ? 2.5 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '$itemNoun ${index + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: page.background.isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${page.strokes.length} strokes',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: page.background.isDark
                                              ? Colors.white60
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (project.pages.length > 1)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        ref
                                            .read(
                                              whiteboardControllerProvider
                                                  .notifier,
                                            )
                                            .deletePage(index);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
