import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../canvas/whiteboard_canvas.dart';
import '../state/whiteboard_notifier.dart';
import 'ai_recognition_settings_dialog.dart';
import 'canvas_zoom_controls.dart';
import 'export_dialog.dart';
import 'math_calculator_dialog.dart';
import 'math_suggestion_overlay.dart';
import 'page_strip_widget.dart';
import 'selection_action_overlay.dart';
import 'shape_suggestion_overlay.dart';
import 'tool_properties_panel.dart';
import 'toolbar_widget.dart';
import 'unified_bottom_bar.dart';

class WhiteboardScreen extends ConsumerStatefulWidget {
  const WhiteboardScreen({super.key});

  @override
  ConsumerState<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends ConsumerState<WhiteboardScreen> {
  bool _isPropertiesOpen = false;
  bool _isToolbarVisible = true;
  Offset? _toolbarPosition;

  void _toggleProperties() {
    setState(() {
      _isPropertiesOpen = !_isPropertiesOpen;
    });
  }

  void _onToolbarDragUpdate(DragUpdateDetails details) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    setState(() {
      final cur =
          _toolbarPosition ?? Offset(screenSize.width - 68, topPadding + 16);
      _toolbarPosition = Offset(
        (cur.dx + details.delta.dx).clamp(10.0, screenSize.width - 68),
        (cur.dy + details.delta.dy)
            .clamp(topPadding + 10, screenSize.height - 420),
      );
    });
  }

  void _editTitle(BuildContext context, String currentTitle) {
    final titleController = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Board'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Board Title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(whiteboardControllerProvider.notifier)
                  .renameProject(titleController.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Home',
          onPressed: () async {
            // Auto-save before popping
            await ref.read(whiteboardControllerProvider.notifier).saveProject();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: GestureDetector(
          onTap: () => _editTitle(context, state.project.title),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  state.project.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
            ],
          ),
        ),
        actions: [
          // Undo Button
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Undo',
            onPressed: state.canUndo
                ? () => ref.read(whiteboardControllerProvider.notifier).undo()
                : null,
          ),

          // Redo Button
          IconButton(
            icon: const Icon(Icons.redo_rounded),
            tooltip: 'Redo',
            onPressed: state.canRedo
                ? () => ref.read(whiteboardControllerProvider.notifier).redo()
                : null,
          ),

          const SizedBox(width: 4),

          // Save Button
          IconButton(
            icon: state.isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_done_outlined),
            tooltip: 'Save Board',
            onPressed: () async {
              await ref
                  .read(whiteboardControllerProvider.notifier)
                  .saveProject();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Board saved locally'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),

          // Math Equation Solver & Auto-Calculation
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'Math & Equation Solver',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => const MathCalculatorDialog(),
              );
            },
          ),

          // Export & Share Button
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Export & Share',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => const ExportDialog(),
              );
            },
          ),

          // Smart Recognition & AI Automation Settings
          IconButton(
            icon: Icon(
              Icons.auto_awesome_rounded,
              color: (state.isAutoMathEnabled || state.isAutoShapeEnabled)
                  ? const Color(0xFF059669)
                  : Colors.grey,
            ),
            tooltip: 'Smart Recognition & AI Settings',
            onPressed: () => AiRecognitionSettingsDialog.show(context),
          ),

          // Canvas Mode Toggle (Paginated Sheet vs Infinite Canvas)
          IconButton(
            icon: Icon(
              state.isInfiniteCanvas
                  ? Icons.all_inclusive_rounded
                  : Icons.auto_stories_rounded,
              color: state.isInfiniteCanvas
                  ? const Color(0xFF6366F1)
                  : Theme.of(context).colorScheme.primary,
            ),
            tooltip: state.isInfiniteCanvas
                ? 'Canvas Mode: Infinite (Tap to switch to Paginated)'
                : 'Canvas Mode: Paginated (Tap to switch to Infinite)',
            onPressed: () {
              ref
                  .read(whiteboardControllerProvider.notifier)
                  .toggleCanvasMode();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    !state.isInfiniteCanvas
                        ? '♾️ Switched to Infinite Canvas (Boundless)'
                        : '📄 Switched to Paginated Mode (Page Sheet)',
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),

          // Toggle Toolbar Show/Hide
          IconButton(
            icon: Icon(
              _isToolbarVisible
                  ? Icons.view_sidebar_rounded
                  : Icons.view_sidebar_outlined,
              color: _isToolbarVisible
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: _isToolbarVisible ? 'Hide Toolbar' : 'Show Toolbar',
            onPressed: () {
              setState(() {
                _isToolbarVisible = !_isToolbarVisible;
              });
            },
          ),

          // Background & Properties Toggle
          IconButton(
            icon: Icon(
              Icons.palette_outlined,
              color: _isPropertiesOpen
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: 'Colors & Canvas Settings',
            onPressed: _toggleProperties,
          ),

          const SizedBox(width: 8),
        ],
      ),
      body: Builder(
        builder: (context) {
          final screenSize = MediaQuery.of(context).size;
          final topPadding = MediaQuery.of(context).padding.top;
          final isDark = Theme.of(context).brightness == Brightness.dark;

          // Initialize default toolbar position
          _toolbarPosition ??= Offset(
            state.isLeftHanded ? 16 : (screenSize.width - 68),
            topPadding + 16,
          );

          return Stack(
            children: [
              // Canvas fills 100% of workspace
              const Positioned.fill(
                child: WhiteboardCanvas(),
              ),

              // Shape Suggestion Floating Overlay
              const Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: ShapeSuggestionOverlay(),
              ),

              // Handwritten Math Calculation Floating Overlay
              const Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: MathSuggestionOverlay(),
              ),

              // Floating Draggable Toolbar
              if (_isToolbarVisible)
                Positioned(
                  left: _toolbarPosition!.dx,
                  top: _toolbarPosition!.dy,
                  child: WhiteboardToolbar(
                    isPropertiesOpen: _isPropertiesOpen,
                    onToggleProperties: _toggleProperties,
                    onHideToolbar: () =>
                        setState(() => _isToolbarVisible = false),
                    onPanUpdate: _onToolbarDragUpdate,
                  ),
                ),

              // Minimized Floating Trigger Button to restore Toolbar when hidden
              if (!_isToolbarVisible)
                Positioned(
                  top: _toolbarPosition!.dy,
                  left: _toolbarPosition!.dx <= screenSize.width / 2
                      ? 12
                      : null,
                  right: _toolbarPosition!.dx > screenSize.width / 2
                      ? 12
                      : null,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(24),
                    color: isDark ? const Color(0xFF1F2937) : Colors.white,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => setState(() => _isToolbarVisible = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.brush_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Tools',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Floating Properties Panel (Positioned adjacent to Draggable Toolbar)
              if (_isPropertiesOpen && _isToolbarVisible)
                Positioned(
                  top: _toolbarPosition!.dy.clamp(16.0, screenSize.height - 400),
                  left: _toolbarPosition!.dx <= screenSize.width / 2
                      ? (_toolbarPosition!.dx + 64)
                      : null,
                  right: _toolbarPosition!.dx > screenSize.width / 2
                      ? (screenSize.width - _toolbarPosition!.dx + 8)
                      : null,
                  child: const ToolPropertiesPanel(),
                ),

              // Bottom Floating Unified Whiteboard Controls (Single slim bar)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 16,
                right: 16,
                child: const UnifiedBottomBar(),
              ),
            ],
          );
        },
      ),
    );
  }
}
