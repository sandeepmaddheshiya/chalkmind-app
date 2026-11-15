import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../canvas/whiteboard_canvas.dart';
import '../models/tool_type.dart';
import 'ai_assistant_panel.dart';
import '../../onboarding/coach_marks.dart';
import '../../onboarding/onboarding_prefs.dart';
import 'canvas_zoom_controls.dart';
import '../state/whiteboard_notifier.dart';
import 'ai_recognition_settings_dialog.dart';
import 'export_dialog.dart';
import 'math_suggestion_overlay.dart';
import 'pdf_lookup_overlay.dart';
import '../pdf/pdf_import_flow.dart';
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
  // Targets for the step-by-step tutorial spotlight.
  final _toolbarKey = GlobalKey(debugLabel: 'tour-toolbar');
  final _undoRedoKey = GlobalKey(debugLabel: 'tour-undo');
  final _aiKey = GlobalKey(debugLabel: 'tour-ai');
  final _moreKey = GlobalKey(debugLabel: 'tour-more');
  final _bottomBarKey = GlobalKey(debugLabel: 'tour-bottom');
  final _toolKeys = <ToolType, GlobalKey>{
    ToolType.pen: GlobalKey(debugLabel: 'tour-pen'),
    ToolType.highlighter: GlobalKey(debugLabel: 'tour-highlighter'),
    ToolType.strokeEraser: GlobalKey(debugLabel: 'tour-eraser'),
    ToolType.shape: GlobalKey(debugLabel: 'tour-shapes'),
    ToolType.select: GlobalKey(debugLabel: 'tour-select'),
  };
  bool _tourRunning = false;

  @override
  void initState() {
    super.initState();
    // First board visit: offer the step-by-step tutorial once.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await OnboardingPrefs.isTutorialDone() || !mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) _startTour();
    });
  }

  List<CoachStep> _tourSteps() {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return [
      const CoachStep(
        icon: Icons.waving_hand_rounded,
        title: 'Quick tour',
        body:
            'A 1-minute walk through the board. You can replay it any time from the menu.',
      ),
      CoachStep(
        target: _toolbarKey,
        icon: Icons.construction_rounded,
        title: 'Your toolbar',
        body:
            'All drawing tools live here. Drag the dots at the top to move it, or hide it from the menu.',
      ),
      CoachStep(
        target: _toolKeys[ToolType.pen],
        icon: Icons.edit_rounded,
        title: 'Write and draw',
        body:
            'Pen, pencil and marker. Tap the round colour button above to change colour and thickness.',
      ),
      CoachStep(
        target: _toolKeys[ToolType.highlighter],
        icon: Icons.border_color_rounded,
        title: 'Highlighter',
        body:
            'Mark important parts. On an imported PDF, highlight a word to see its meaning.',
      ),
      CoachStep(
        target: _toolKeys[ToolType.strokeEraser],
        icon: Icons.auto_fix_normal_rounded,
        title: 'Eraser',
        body:
            'Swipe to erase whole strokes. Tap the eraser again to erase only the part you touch.',
      ),
      CoachStep(
        target: _toolKeys[ToolType.shape],
        icon: Icons.category_rounded,
        title: 'Shapes',
        body:
            'Draw perfect shapes. Even with the pen, rough circles and boxes offer to snap into neat ones.',
      ),
      CoachStep(
        target: _toolKeys[ToolType.select],
        icon: Icons.highlight_alt_rounded,
        title: 'Select',
        body:
            'Circle anything to move, copy or delete it, or tap "Solve" to have the selection worked out.',
      ),
      CoachStep(
        target: _undoRedoKey,
        icon: Icons.undo_rounded,
        title: 'Undo & redo',
        body: 'Every page keeps its own history, so you can always step back.',
      ),
      CoachStep(
        target: _aiKey,
        icon: Icons.psychology_alt_rounded,
        title: 'AI Assistant',
        body:
            'Explain, give hints, check working, make quizzes or draw flowcharts from what is on the board.',
      ),
      CoachStep(
        target: _moreKey,
        icon: Icons.more_horiz_rounded,
        title: 'More actions',
        body: compact
            ? 'Import PDF pages, export or share, smart recognition settings, and replay this tour.'
            : 'Import PDF pages, export or share, smart recognition settings, canvas mode and colours.',
      ),
      CoachStep(
        target: _bottomBarKey,
        icon: Icons.layers_outlined,
        title: 'Pages & zoom',
        body:
            'Add and switch pages, zoom in and out, or fit everything on screen. Pinch to zoom works too.',
      ),
      const CoachStep(
        icon: Icons.functions_rounded,
        title: 'Try it now',
        body:
            'Write 2 + 3 = with the pen. Chalkmind will offer the answer in your handwriting.',
      ),
    ];
  }

  Future<void> _startTour() async {
    if (_tourRunning) return;
    _tourRunning = true;
    // Make sure the targets are visible.
    if (!_isToolbarVisible || _isAssistantOpen) {
      setState(() {
        _isToolbarVisible = true;
        _isAssistantOpen = false;
      });
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    await CoachMarkTour.show(context, _tourSteps());
    _tourRunning = false;
    await OnboardingPrefs.markTutorialDone();
    if (mounted) _boardFocus.requestFocus();
  }

  final FocusNode _boardFocus = FocusNode(debugLabel: 'whiteboard');
  bool _isAssistantOpen = false;
  ToolType? _toolBeforeSpacePan;
  bool _isLeaving = false;
  bool _isPropertiesOpen = false;
  bool _isToolbarVisible = true;
  Offset? _toolbarPosition;

  @override
  void dispose() {
    _boardFocus.dispose();
    super.dispose();
  }

  /// Saves, reporting failure. Returns true when saved.
  Future<bool> _save({bool showSuccess = false}) async {
    try {
      await ref.read(whiteboardControllerProvider.notifier).saveProject();
      if (showSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Board saved'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save the board: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return false;
    }
  }

  /// Leaves the board after saving. If saving fails the user is asked
  /// whether to leave anyway (the crash-recovery draft is kept).
  Future<void> _leave() async {
    if (_isLeaving) return;
    _isLeaving = true;
    final saved = await _save();
    if (!mounted) return;
    if (!saved) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave without saving?'),
          content: const Text(
            'The board could not be saved. Your latest changes are kept as a recovery draft you can restore from the home screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) {
        _isLeaving = false;
        return;
      }
    }
    Navigator.of(context).pop();
  }

  bool get _isTyping {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final notifier = ref.read(whiteboardControllerProvider.notifier);
    final key = event.logicalKey;

    // Hold Space to pan temporarily.
    if (key == LogicalKeyboardKey.space && !_isTyping) {
      if (event is KeyDownEvent && _toolBeforeSpacePan == null) {
        final current = ref.read(whiteboardControllerProvider).currentTool;
        if (current != ToolType.hand) {
          _toolBeforeSpacePan = current;
          notifier.setTool(ToolType.hand);
        }
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent && _toolBeforeSpacePan != null) {
        notifier.setTool(_toolBeforeSpacePan!);
        _toolBeforeSpacePan = null;
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_isTyping) return KeyEventResult.ignored;

    final keys = HardwareKeyboard.instance;
    final mod = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    void zoom(CanvasZoomAction a) =>
        ref.read(canvasZoomActionProvider.notifier).trigger(a);

    if (mod) {
      if (key == LogicalKeyboardKey.keyZ) {
        shift ? notifier.redo() : notifier.undo();
      } else if (key == LogicalKeyboardKey.keyY) {
        notifier.redo();
      } else if (key == LogicalKeyboardKey.keyC) {
        notifier.copySelected();
      } else if (key == LogicalKeyboardKey.keyX) {
        notifier.cutSelected();
      } else if (key == LogicalKeyboardKey.keyV) {
        notifier.pasteClipboard();
      } else if (key == LogicalKeyboardKey.keyD) {
        notifier.duplicateSelected();
      } else if (key == LogicalKeyboardKey.keyA) {
        notifier.selectAll();
      } else if (key == LogicalKeyboardKey.keyS) {
        _save(showSuccess: true);
      } else if (key == LogicalKeyboardKey.keyK) {
        setState(() => _isAssistantOpen = !_isAssistantOpen);
      } else if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd) {
        zoom(CanvasZoomAction.zoomIn);
      } else if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        zoom(CanvasZoomAction.zoomOut);
      } else if (key == LogicalKeyboardKey.digit0 ||
          key == LogicalKeyboardKey.numpad0) {
        zoom(CanvasZoomAction.reset);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (shift && key == LogicalKeyboardKey.digit1) {
      zoom(CanvasZoomAction.fitContent);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      notifier.deleteSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      notifier.clearSelection();
      notifier.dismissShapeSuggestion();
      notifier.dismissHandwrittenMath();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      notifier.nextPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      notifier.previousPage();
      return KeyEventResult.handled;
    }
    final toolKeys = <LogicalKeyboardKey, ToolType>{
      LogicalKeyboardKey.keyP: ToolType.pen,
      LogicalKeyboardKey.keyM: ToolType.marker,
      LogicalKeyboardKey.keyH: ToolType.highlighter,
      LogicalKeyboardKey.keyE: ToolType.strokeEraser,
      LogicalKeyboardKey.keyS: ToolType.shape,
      LogicalKeyboardKey.keyT: ToolType.text,
      LogicalKeyboardKey.keyV: ToolType.select,
      LogicalKeyboardKey.keyL: ToolType.laser,
    };
    final tool = toolKeys[key];
    if (tool != null) {
      final current = ref.read(whiteboardControllerProvider).currentTool;
      // Pressing E again toggles whole-stroke / partial erasing.
      if (tool == ToolType.strokeEraser && current == ToolType.strokeEraser) {
        notifier.setTool(ToolType.areaEraser);
      } else {
        notifier.setTool(tool);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<({Widget icon, String label, VoidCallback onTap})> _secondaryActions(
    BuildContext context, {
    required bool autoOn,
    required bool infinite,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return [
      (
        icon: const Icon(Icons.school_outlined),
        label: 'Show tutorial',
        onTap: _startTour,
      ),
      (
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: 'Import PDF pages',
        onTap: _importPdfPages,
      ),
      (
        icon: const Icon(Icons.share_rounded),
        label: 'Export & Share',
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const ExportDialog(),
        ),
      ),
      (
        icon: Icon(
          Icons.auto_awesome_rounded,
          color: autoOn ? const Color(0xFF059669) : Colors.grey,
        ),
        label: 'Smart Recognition & AI Settings',
        onTap: () => AiRecognitionSettingsDialog.show(context),
      ),
      (
        icon: Icon(
          infinite ? Icons.all_inclusive_rounded : Icons.auto_stories_rounded,
          color: infinite ? const Color(0xFF6366F1) : primary,
        ),
        label: infinite
            ? 'Canvas: Infinite (switch to Paginated)'
            : 'Canvas: Paginated (switch to Infinite)',
        onTap: () {
          ref.read(whiteboardControllerProvider.notifier).toggleCanvasMode();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                !infinite
                    ? 'Switched to Infinite Canvas'
                    : 'Switched to Paginated Mode',
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
      (
        icon: Icon(
          _isToolbarVisible
              ? Icons.view_sidebar_rounded
              : Icons.view_sidebar_outlined,
          color: _isToolbarVisible ? primary : null,
        ),
        label: _isToolbarVisible ? 'Hide Toolbar' : 'Show Toolbar',
        onTap: () => setState(() => _isToolbarVisible = !_isToolbarVisible),
      ),
      (
        icon: Icon(
          Icons.palette_outlined,
          color: _isPropertiesOpen ? primary : null,
        ),
        label: 'Colors & Canvas Settings',
        onTap: _toggleProperties,
      ),
    ];
  }

  /// Adds a PDF's pages after the current page.
  Future<void> _importPdfPages() async {
    final s = ref.read(whiteboardControllerProvider);
    final result = await PdfImportFlow.pickAndImport(
      context,
      background: s.project.currentPage.background,
      firstPageNumber: s.project.currentPageIndex + 2,
    );
    if (result == null || !mounted) return;
    ref.read(whiteboardControllerProvider.notifier).insertPages(result.pages);
    await _save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${result.pages.length} PDF page(s). Use the highlighter on text to look it up.',
          ),
        ),
      );
    }
  }

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
        (cur.dy + details.delta.dy).clamp(
          topPadding + 10,
          screenSize.height - 420,
        ),
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
    // Watch only what the app bar and layout need, so zoom/pan and drawing
    // don't rebuild the whole screen.
    final state = ref.watch(
      whiteboardControllerProvider.select(
        (s) => (
          project: (title: s.project.title, id: s.project.id),
          canUndo: s.canUndo,
          canRedo: s.canRedo,
          isSaving: s.isSaving,
          isAutoMathEnabled: s.isAutoMathEnabled,
          isAutoShapeEnabled: s.isAutoShapeEnabled,
          isInfiniteCanvas: s.isInfiniteCanvas,
          isLeftHanded: s.isLeftHanded,
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Focus(
        focusNode: _boardFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back to Home',
              onPressed: _leave,
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
                ],
              ),
            ),
            actions: [
              // Undo / Redo (grouped so the tutorial can point at both)
              Row(
                key: _undoRedoKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.undo_rounded),
                    tooltip: 'Undo (Ctrl+Z)',
                    onPressed: state.canUndo
                        ? () => ref
                              .read(whiteboardControllerProvider.notifier)
                              .undo()
                        : null,
                  ),

                  // Redo Button
                  IconButton(
                    icon: const Icon(Icons.redo_rounded),
                    tooltip: 'Redo (Ctrl+Shift+Z)',
                    onPressed: state.canRedo
                        ? () => ref
                              .read(whiteboardControllerProvider.notifier)
                              .redo()
                        : null,
                  ),
                ],
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
                tooltip: 'Save Board (Ctrl+S)',
                onPressed: () => _save(showSuccess: true),
              ),

              // AI Assistant (board-aware tutor, generator, diagram maker)
              IconButton(
                key: _aiKey,
                icon: Icon(
                  Icons.psychology_alt_rounded,
                  color: _isAssistantOpen
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                tooltip: 'AI Assistant (Ctrl+K)',
                onPressed: () =>
                    setState(() => _isAssistantOpen = !_isAssistantOpen),
              ),

              // Secondary actions: inline on wide screens, overflow menu on
              // phones (they overflowed the app bar below ~760px).
              if (MediaQuery.sizeOf(context).width >= 760)
                Row(
                  key: _moreKey,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in _secondaryActions(
                      context,
                      autoOn:
                          state.isAutoMathEnabled || state.isAutoShapeEnabled,
                      infinite: state.isInfiniteCanvas,
                    ))
                      IconButton(
                        icon: a.icon,
                        tooltip: a.label,
                        onPressed: a.onTap,
                      ),
                  ],
                )
              else
                PopupMenuButton<int>(
                  key: _moreKey,
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_vert_rounded),
                  itemBuilder: (menuContext) {
                    final items = _secondaryActions(
                      context,
                      autoOn:
                          state.isAutoMathEnabled || state.isAutoShapeEnabled,
                      infinite: state.isInfiniteCanvas,
                    );
                    return [
                      for (final a in items)
                        PopupMenuItem<int>(
                          onTap: a.onTap,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: a.icon,
                            title: Text(a.label),
                          ),
                        ),
                    ];
                  },
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
                  const Positioned.fill(child: WhiteboardCanvas()),

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

                  // Look-up offer after highlighting text on a PDF page
                  const Positioned(
                    top: 14,
                    left: 12,
                    right: 12,
                    child: PdfLookupOverlay(),
                  ),

                  // Floating Draggable Toolbar
                  if (_isToolbarVisible)
                    Positioned(
                      left: _toolbarPosition!.dx,
                      top: _toolbarPosition!.dy,
                      child: WhiteboardToolbar(
                        key: _toolbarKey,
                        toolKeys: _toolKeys,
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
                              horizontal: 10,
                              vertical: 8,
                            ),
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
                      top: _toolbarPosition!.dy.clamp(
                        16.0,
                        screenSize.height - 400,
                      ),
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
                    child: UnifiedBottomBar(key: _bottomBarKey),
                  ),

                  // AI Assistant side panel (non-modal: drawing continues while
                  // the AI responds).
                  if (_isAssistantOpen)
                    Positioned(
                      top: 8,
                      bottom: MediaQuery.of(context).padding.bottom + 76,
                      right: 8,
                      width: (screenSize.width - 16).clamp(280.0, 420.0),
                      child: AiAssistantPanel(
                        onClose: () {
                          setState(() => _isAssistantOpen = false);
                          _boardFocus.requestFocus();
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
