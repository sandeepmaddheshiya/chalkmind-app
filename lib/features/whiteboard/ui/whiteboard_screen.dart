import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../canvas/whiteboard_canvas.dart';
import '../state/whiteboard_notifier.dart';
import 'ai_recognition_settings_dialog.dart';
import 'export_dialog.dart';
import 'math_calculator_dialog.dart';
import 'math_suggestion_overlay.dart';
import 'page_strip_widget.dart';
import 'selection_action_overlay.dart';
import 'shape_suggestion_overlay.dart';
import 'tool_properties_panel.dart';
import 'toolbar_widget.dart';

class WhiteboardScreen extends ConsumerStatefulWidget {
  const WhiteboardScreen({super.key});

  @override
  ConsumerState<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends ConsumerState<WhiteboardScreen> {
  bool _isPropertiesOpen = false;

  void _toggleProperties() {
    setState(() {
      _isPropertiesOpen = !_isPropertiesOpen;
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
      body: Stack(
        children: [
          // Canvas fills 100% of workspace
          const Positioned.fill(
            child: WhiteboardCanvas(),
          ),

          // Shape Suggestion Floating Overlay (e.g. "Convert to Circle? [Convert] [Keep]")
          const Positioned(
            top: 14,
            left: 0,
            right: 0,
            child: ShapeSuggestionOverlay(),
          ),

          // Handwritten Math Calculation Floating Overlay (e.g. "2 + 2 = 4 [Write 4 in Ink]")
          const Positioned(
            top: 14,
            left: 0,
            right: 0,
            child: MathSuggestionOverlay(),
          ),

          // Floating Toolbar (Left or Right depending on left-handed setting)
          Positioned(
            top: 16,
            left: state.isLeftHanded ? 16 : null,
            right: state.isLeftHanded ? null : 16,
            child: WhiteboardToolbar(
              isPropertiesOpen: _isPropertiesOpen,
              onToggleProperties: _toggleProperties,
            ),
          ),

          // Floating Properties Panel (Placed next to toolbar when open)
          if (_isPropertiesOpen)
            Positioned(
              top: 16,
              left: state.isLeftHanded ? 80 : null,
              right: state.isLeftHanded ? null : 80,
              child: const ToolPropertiesPanel(),
            ),

          // Floating Selection Action Bar (Solve Selected, Delete, Clear)
          const Positioned(
            bottom: 84,
            left: 0,
            right: 0,
            child: SelectionActionOverlay(),
          ),

          // Bottom Floating Page Strip & Navigation
          const Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: PageStripWidget(),
            ),
          ),
        ],
      ),
    );
  }
}
