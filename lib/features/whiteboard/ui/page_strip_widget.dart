import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/whiteboard_notifier.dart';

class PageStripWidget extends ConsumerWidget {
  const PageStripWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final currentPageIndex = state.project.currentPageIndex;
    final totalPages = state.project.totalPages;

    final isInfinite = state.isInfiniteCanvas;
    final itemNoun = isInfinite ? 'Board' : 'Page';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // If elements are selected, show selection action buttons
          if (state.selectedObjectIds.isNotEmpty) ...[
            Text(
              '${state.selectedObjectIds.length} selected',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
                size: 20,
              ),
              tooltip: 'Delete Selected',
              onPressed: () {
                ref
                    .read(whiteboardControllerProvider.notifier)
                    .deleteSelected();
              },
            ),
            Container(
              width: 1,
              height: 20,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              margin: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ],

          // Previous Page/Board Button
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 24),
            tooltip: 'Previous $itemNoun',
            onPressed: currentPageIndex > 0
                ? () {
                    ref
                        .read(whiteboardControllerProvider.notifier)
                        .previousPage();
                  }
                : null,
          ),

          // Page/Board Counter Indicator
          GestureDetector(
            onTap: () => _showPageOverviewSheet(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isInfinite
                        ? Icons.all_inclusive_rounded
                        : Icons.auto_stories_rounded,
                    size: 14,
                    color: isInfinite
                        ? const Color(0xFF6366F1)
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$itemNoun ${currentPageIndex + 1} of $totalPages',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Next Page/Board Button
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 24),
            tooltip: 'Next $itemNoun',
            onPressed: currentPageIndex < totalPages - 1
                ? () {
                    ref.read(whiteboardControllerProvider.notifier).nextPage();
                  }
                : null,
          ),

          Container(
            width: 1,
            height: 20,
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),

          // Add New Page/Board Button
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 22),
            tooltip: 'Add New $itemNoun',
            onPressed: () {
              ref.read(whiteboardControllerProvider.notifier).addNewPage();
            },
          ),

          // Duplicate Current Page/Board
          IconButton(
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            tooltip: 'Duplicate $itemNoun',
            onPressed: () {
              ref
                  .read(whiteboardControllerProvider.notifier)
                  .duplicateCurrentPage();
            },
          ),

          // Clear Current Page/Board
          IconButton(
            icon: const Icon(Icons.clear_all_rounded, size: 22),
            tooltip: 'Clear $itemNoun',
            onPressed: () => _confirmClearPage(context, ref),
          ),
        ],
      ),
    );
  }

  void _confirmClearPage(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Current Page?'),
        content: const Text(
          'This will remove all drawings, shapes, and notes from this page. You can undo this action.',
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
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showPageOverviewSheet(BuildContext context, WidgetRef ref) {
    final state = ref.read(whiteboardControllerProvider);
    final pages = state.project.pages;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pages Overview',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('New Page'),
                    onPressed: () {
                      ref
                          .read(whiteboardControllerProvider.notifier)
                          .addNewPage();
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: pages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, idx) {
                    final page = pages[idx];
                    final isCurrent = idx == state.project.currentPageIndex;

                    return GestureDetector(
                      onTap: () {
                        ref
                            .read(whiteboardControllerProvider.notifier)
                            .selectPage(idx);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        width: 120,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: page.background.color,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                            width: isCurrent ? 3 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Page ${idx + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: page.background.isDark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            Text(
                              '${page.totalElements} elements',
                              style: TextStyle(
                                fontSize: 11,
                                color: page.background.isDark
                                    ? Colors.white70
                                    : Colors.black54,
                              ),
                            ),
                            if (pages.length > 1)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                tooltip: 'Delete Page',
                                onPressed: () {
                                  ref
                                      .read(
                                        whiteboardControllerProvider.notifier,
                                      )
                                      .deleteCurrentPage();
                                  Navigator.pop(ctx);
                                },
                              )
                            else
                              const SizedBox(height: 16),
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
  }
}
