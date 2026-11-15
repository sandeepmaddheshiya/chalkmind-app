import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../pdf/pdf_page_renderer.dart';
import '../models/page_model.dart';
import '../models/pdf_page_attachment.dart';
import '../models/shape_model.dart';
import '../models/stroke_model.dart';
import '../models/stroke_point.dart';
import '../models/text_model.dart';
import '../models/tool_type.dart';
import '../rendering/active_stroke_painter.dart';
import '../rendering/background_painter.dart';
import '../rendering/board_painter.dart';
import '../rendering/selection_painter.dart';
import '../state/whiteboard_notifier.dart';
import '../ui/canvas_zoom_controls.dart';
import '../ui/interactive_plot_widget.dart';

/// Transient, high-frequency gesture state (active ink, previews, cursors).
///
/// Lives outside the widget tree's build cycle: pointer moves mutate it and
/// call [changed], which repaints only the overlay painters listening to it.
/// This avoids rebuilding the whole canvas subtree on every pointer event.
class _LiveGesture extends ChangeNotifier {
  final List<StrokePoint> points = [];
  Offset? shapeStart;
  Offset? shapeEnd;
  Offset? eraser;
  Offset? laser;
  Rect? marquee;
  Offset dragOffset = Offset.zero;

  void changed() => notifyListeners();

  void clearAll() {
    points.clear();
    shapeStart = null;
    shapeEnd = null;
    eraser = null;
    laser = null;
    marquee = null;
    dragOffset = Offset.zero;
    notifyListeners();
  }
}

class WhiteboardCanvas extends ConsumerStatefulWidget {
  const WhiteboardCanvas({super.key});

  @override
  ConsumerState<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends ConsumerState<WhiteboardCanvas> {
  final TransformationController _transformController =
      TransformationController();
  final _LiveGesture _gesture = _LiveGesture();

  // Selection drag
  Offset? _dragStart;
  bool _isPressingSelection = false; // pointer down on selection, not yet moved
  bool _isMovingSelected = false; // drag preview active (hides originals)

  // Eraser
  Offset? _lastErasePoint;

  // Double-tap-to-edit text (select tool)
  String? _lastTapTextId;
  DateTime? _lastTapTime;

  // Robust pointer & palm rejection tracking
  int? _drawingPointerId;
  bool _isDrawingWithStylus = false;
  DateTime? _drawingStartTime;
  final Map<int, Offset> _activePointers = {}; // local coordinates
  Offset? _handPanLastPos;
  bool _twoFingerActive = false;
  double? _lastPinchDistance;
  Offset? _lastTwoFingerMidpoint;

  // Trackpad pan/zoom
  double _lastTrackpadScale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    ref
        .read(whiteboardControllerProvider.notifier)
        .setZoomAndPan(
          scale,
          Offset(
            _transformController.value.entry(0, 3),
            _transformController.value.entry(1, 3),
          ),
        );
  }

  void _panBy(Offset screenDelta) {
    final matrix = _transformController.value.clone();
    final currentTx = matrix.entry(0, 3);
    final currentTy = matrix.entry(1, 3);
    matrix.setEntry(0, 3, currentTx + screenDelta.dx);
    matrix.setEntry(1, 3, currentTy + screenDelta.dy);
    _transformController.value = matrix;
  }

  void _zoomAround(
    Offset focalPoint,
    double factor, {
    required bool isInfinite,
  }) {
    final matrix = _transformController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final minScale = isInfinite ? 0.10 : 0.40;
    final maxScale = isInfinite ? 6.0 : 3.5;
    final targetScale = (currentScale * factor).clamp(minScale, maxScale);
    final actualRatio = targetScale / currentScale;

    final currentTx = matrix.entry(0, 3);
    final currentTy = matrix.entry(1, 3);

    final newTx = focalPoint.dx - (focalPoint.dx - currentTx) * actualRatio;
    final newTy = focalPoint.dy - (focalPoint.dy - currentTy) * actualRatio;

    matrix.scaleByDouble(actualRatio, actualRatio, 1.0, 1.0);
    matrix.setEntry(0, 3, newTx);
    matrix.setEntry(1, 3, newTy);
    _transformController.value = matrix;
  }

  void _zoomBy(double factor) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final center = renderBox != null
        ? renderBox.size.center(Offset.zero)
        : const Offset(400, 600);
    final isInfinite = ref.read(whiteboardControllerProvider).isInfiniteCanvas;
    _zoomAround(center, factor, isInfinite: isInfinite);
  }

  void _resetTransform() {
    _transformController.value = Matrix4.identity();
  }

  /// Zooms and pans so all content on the page is visible.
  void _fitToContent() {
    final page = ref.read(whiteboardControllerProvider).project.currentPage;
    final bounds = _contentBounds(page);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (bounds == null || renderBox == null) {
      _resetTransform();
      return;
    }
    final viewport = renderBox.size;
    final padded = bounds.inflate(48);
    final isInfinite = ref.read(whiteboardControllerProvider).isInfiniteCanvas;
    final scale = (viewport.width / padded.width)
        .clamp(0.0, viewport.height / padded.height)
        .clamp(isInfinite ? 0.10 : 0.40, 2.0)
        .toDouble();
    final tx =
        (viewport.width - padded.width * scale) / 2 - padded.left * scale;
    final ty =
        (viewport.height - padded.height * scale) / 2 - padded.top * scale;
    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  static Rect? _contentBounds(PageModel page) {
    Rect? r;
    void add(Rect b) => r = r == null ? b : r!.expandToInclude(b);
    for (final s in page.strokes) {
      add(s.bounds);
    }
    for (final s in page.shapes) {
      add(s.bounds);
    }
    for (final t in page.texts) {
      add(t.bounds);
    }
    for (final p in page.plots) {
      add(p.rect);
    }
    return r;
  }

  /// PDF pages just before and after the current one, for prefetching.
  List<PdfPageAttachment> _neighbourPdfPages() {
    final project = ref.read(whiteboardControllerProvider).project;
    final i = project.currentPageIndex;
    return [
      for (final j in [i + 1, i - 1, i + 2])
        if (j >= 0 && j < project.pages.length && project.pages[j].pdf != null) project.pages[j].pdf!,
    ];
  }

  Offset _toCanvasPoint(Offset screenPoint) {
    try {
      return _transformController.toScene(screenPoint);
    } catch (_) {
      final matrix = _transformController.value;
      final inverse = Matrix4.inverted(matrix);
      return MatrixUtils.transformPoint(inverse, screenPoint);
    }
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _gesture.dispose();
    super.dispose();
  }

  void _cancelActiveGesture() {
    final notifier = ref.read(whiteboardControllerProvider.notifier);
    if (_lastErasePoint != null) {
      notifier.endEraseGesture();
      _lastErasePoint = null;
    }
    if (_isMovingSelected) {
      setState(() => _isMovingSelected = false);
    }
    _isPressingSelection = false;
    _dragStart = null;
    _gesture.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    // Watch only what the canvas renders. Zoom/pan are deliberately excluded:
    // they're applied through the TransformationController, so pinch-zoom
    // never rebuilds this subtree.
    final view = ref.watch(
      whiteboardControllerProvider.select(
        (s) => (
          page: s.project.currentPage,
          tool: s.currentTool,
          selected: s.selectedObjectIds,
          infinite: s.isInfiniteCanvas,
          color: s.selectedColorValue,
          width: s.selectedStrokeWidth,
          shapeType: s.selectedShapeType,
          filled: s.isShapeFilled,
        ),
      ),
    );
    final currentPage = view.page;
    final isInfinite = view.infinite;

    // Listen for zoom actions from floating zoom toolbar
    ref.listen<CanvasZoomAction>(canvasZoomActionProvider, (prev, next) {
      if (next == CanvasZoomAction.none) return;
      switch (next) {
        case CanvasZoomAction.zoomIn:
          _zoomBy(1.25);
        case CanvasZoomAction.zoomOut:
          _zoomBy(0.80);
        case CanvasZoomAction.reset:
          _resetTransform();
        case CanvasZoomAction.fitContent:
          _fitToContent();
        case CanvasZoomAction.panLeft:
          _panBy(const Offset(300, 0));
        case CanvasZoomAction.panRight:
          _panBy(const Offset(-300, 0));
        case CanvasZoomAction.panUp:
          _panBy(const Offset(0, 300));
        case CanvasZoomAction.panDown:
          _panBy(const Offset(0, -300));
        case CanvasZoomAction.none:
          break;
      }
      ref.read(canvasZoomActionProvider.notifier).reset();
    });

    // Bounding box for selected elements
    final selectedIds = view.selected;
    Rect? selectedBounds;
    if (selectedIds.isNotEmpty) {
      void add(Rect b) => selectedBounds = selectedBounds == null
          ? b
          : selectedBounds!.expandToInclude(b);
      for (final s in currentPage.strokes) {
        if (selectedIds.contains(s.id)) add(s.bounds);
      }
      for (final s in currentPage.shapes) {
        if (selectedIds.contains(s.id)) add(s.bounds);
      }
      for (final t in currentPage.texts) {
        if (selectedIds.contains(t.id)) add(t.bounds);
      }
      for (final p in currentPage.plots) {
        if (selectedIds.contains(p.id)) add(p.rect);
      }
    }

    final tool = view.tool;
    final hiddenIds = _isMovingSelected ? selectedIds : const <String>{};

    return Stack(
      children: [
        // Layer 0: Background surface (Infinite Canvas or Paginated Desk + Sheet)
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: BackgroundPainter(
                background: currentPage.background,
                isInfiniteCanvas: isInfinite,
                transformListenable: _transformController,
              ),
            ),
          ),
        ),

        // Layer 1: Interactive canvas content & full-screen touch surface
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (event) => _onPointerSignal(event, isInfinite),
            onPointerPanZoomStart: (_) => _lastTrackpadScale = 1.0,
            onPointerPanZoomUpdate: (event) {
              _panBy(event.panDelta);
              final ratio = event.scale / _lastTrackpadScale;
              if ((ratio - 1).abs() > 0.0005) {
                _zoomAround(event.localPosition, ratio, isInfinite: isInfinite);
              }
              _lastTrackpadScale = event.scale;
            },
            onPointerDown: (event) => _onPointerDown(event, selectedBounds),
            onPointerMove: (event) => _onPointerMove(event, isInfinite),
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _transformController,
                child: SizedBox.expand(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Imported PDF page: the "paper" under all ink.
                      if (currentPage.pdf != null)
                        _PdfPageImage(
                          key: ValueKey(currentPage.pdf!.imagePath),
                          pdf: currentPage.pdf!,
                          neighbours: _neighbourPdfPages(),
                        ),

                      // Committed board content
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: BoardPainter(
                                strokes: currentPage.strokes,
                                shapes: currentPage.shapes,
                                texts: currentPage.texts,
                                hiddenIds: hiddenIds,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Interactive math function plots
                      for (final plot in currentPage.plots)
                        if (_isMovingSelected && selectedIds.contains(plot.id))
                          AnimatedBuilder(
                            key: ValueKey(plot.id),
                            animation: _gesture,
                            builder: (context, _) => InteractivePlotWidget(
                              plot: plot,
                              isDarkCanvas: currentPage.background.isDark,
                              previewOffset: _gesture.dragOffset,
                            ),
                          )
                        else
                          InteractivePlotWidget(
                            key: ValueKey(plot.id),
                            plot: plot,
                            isDarkCanvas: currentPage.background.isDark,
                          ),

                      // Dragged selection preview
                      if (_isMovingSelected)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _DragPreviewPainter(
                                gesture: _gesture,
                                page: currentPage,
                                ids: selectedIds,
                              ),
                            ),
                          ),
                        ),

                      // Selection bounding box & marquee
                      if (tool == ToolType.select)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _LiveSelectionPainter(
                                gesture: _gesture,
                                bounds: selectedBounds,
                                isDragging: _isMovingSelected,
                              ),
                            ),
                          ),
                        ),

                      // Active stroke / gesture in progress
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _LiveGesturePainter(
                              gesture: _gesture,
                              tool: tool,
                              color: Color(view.color),
                              width: view.width,
                              shapeType: view.shapeType,
                              filled: view.filled,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                builder: (context, child) => Transform(
                  transform: _transformController.value,
                  alignment: Alignment.topLeft,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Pointer routing -------------------------------------------------

  void _onPointerSignal(PointerSignalEvent event, bool isInfinite) {
    if (event is PointerScrollEvent) {
      final keys = HardwareKeyboard.instance;
      if (keys.isControlPressed || keys.isMetaPressed) {
        // Ctrl/Cmd + wheel: zoom around the cursor.
        final factor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
        _zoomAround(event.localPosition, factor, isInfinite: isInfinite);
      } else if (keys.isShiftPressed) {
        _panBy(Offset(-event.scrollDelta.dy, 0));
      } else {
        _panBy(-event.scrollDelta);
      }
    } else if (event is PointerScaleEvent) {
      _zoomAround(event.localPosition, event.scale, isInfinite: isInfinite);
    }
  }

  bool _isTouchingPlot(Offset canvasPoint) {
    final page = ref.read(whiteboardControllerProvider).project.currentPage;
    return page.plots.any((p) {
      final touchRect = Rect.fromLTRB(
        p.rect.left - 16,
        p.rect.top - 54, // Includes floating toolbar above plot
        p.rect.right + 16,
        p.rect.bottom + 16,
      );
      return touchRect.contains(canvasPoint);
    });
  }

  void _startTwoFinger() {
    final points = _activePointers.values.toList();
    if (points.length < 2) return;
    _lastTwoFingerMidpoint = (points[0] + points[1]) / 2;
    _lastPinchDistance = (points[0] - points[1]).distance;
    _twoFingerActive = true;
  }

  void _onPointerDown(PointerDownEvent event, Rect? selectedBounds) {
    final tool = ref.read(whiteboardControllerProvider).currentTool;
    final isStylus =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final isMouse = event.kind == PointerDeviceKind.mouse;

    _activePointers[event.pointer] = event.localPosition;

    // Middle mouse button (or right button) pans with any tool.
    if (isMouse &&
        (event.buttons & (kMiddleMouseButton | kSecondaryMouseButton)) != 0) {
      _handPanLastPos = event.localPosition;
      return;
    }

    final canvasPoint = _toCanvasPoint(event.localPosition);

    // Touching an interactive plot or its toolbar: let the plot handle it.
    if (_isTouchingPlot(canvasPoint) && tool != ToolType.select) {
      _drawingPointerId = null;
      return;
    }

    if (tool == ToolType.hand) {
      if (_activePointers.length >= 2) {
        _startTwoFinger();
      } else {
        _handPanLastPos = event.localPosition;
      }
      return;
    }

    // Stylus takes absolute priority for drawing (palm rejection).
    if (isStylus) {
      if (_drawingPointerId != null && !_isDrawingWithStylus) {
        _cancelActiveGesture();
      }
      _drawingPointerId = event.pointer;
      _isDrawingWithStylus = true;
      _drawingStartTime = DateTime.now();
      _handlePointerDown(canvasPoint, event, selectedBounds);
      return;
    }

    // While drawing with stylus, ignore all touch inputs (palm rejection).
    if (_isDrawingWithStylus) return;

    if (_drawingPointerId == null) {
      if (_activePointers.length >= 2) {
        _startTwoFinger();
        return;
      }
      _drawingPointerId = event.pointer;
      _drawingStartTime = DateTime.now();
      _handlePointerDown(canvasPoint, event, selectedBounds);
    } else {
      // A second contact while drawing: a near-simultaneous 2-finger touch
      // means pan/zoom; otherwise it's a palm and the stroke continues.
      final elapsed = _drawingStartTime != null
          ? DateTime.now().difference(_drawingStartTime!).inMilliseconds
          : 999;
      if (elapsed < 120 && _gesture.points.length <= 2) {
        _drawingPointerId = null;
        _cancelActiveGesture();
        _startTwoFinger();
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event, bool isInfinite) {
    _activePointers[event.pointer] = event.localPosition;

    if (_isDrawingWithStylus && event.pointer != _drawingPointerId) return;

    if (_twoFingerActive && _activePointers.length >= 2) {
      final points = _activePointers.values.toList();
      final mid = (points[0] + points[1]) / 2;
      final dist = (points[0] - points[1]).distance;
      if (_lastTwoFingerMidpoint != null) {
        _panBy(mid - _lastTwoFingerMidpoint!);
      }
      _lastTwoFingerMidpoint = mid;
      if (_lastPinchDistance != null && _lastPinchDistance! > 10 && dist > 10) {
        _zoomAround(mid, dist / _lastPinchDistance!, isInfinite: isInfinite);
      }
      _lastPinchDistance = dist;
      return;
    }

    if (_handPanLastPos != null && event.pointer != _drawingPointerId) {
      _panBy(event.localPosition - _handPanLastPos!);
      _handPanLastPos = event.localPosition;
      return;
    }

    if (event.pointer == _drawingPointerId) {
      _handlePointerMove(_toCanvasPoint(event.localPosition), event);
    }
  }

  void _resetPointerTracking(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      _twoFingerActive = false;
      _lastTwoFingerMidpoint = null;
      _lastPinchDistance = null;
    }
    if (_activePointers.isEmpty) {
      _handPanLastPos = null;
      _twoFingerActive = false;
      _drawingPointerId = null;
      _isDrawingWithStylus = false;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer == _drawingPointerId) {
      _handlePointerUp(_toCanvasPoint(event.localPosition));
      _drawingPointerId = null;
      _isDrawingWithStylus = false;
    }
    _resetPointerTracking(event);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _drawingPointerId) {
      final tool = ref.read(whiteboardControllerProvider).currentTool;
      // Commit a substantial stroke rather than losing it.
      if (tool.isDrawingTool && _gesture.points.length >= 2) {
        _handlePointerUp(_toCanvasPoint(event.localPosition));
      } else {
        _cancelActiveGesture();
      }
      _drawingPointerId = null;
      _isDrawingWithStylus = false;
    }
    _resetPointerTracking(event);
  }

  // --- Tool behaviour ----------------------------------------------------

  StrokePoint _point(Offset p, PointerEvent event) => StrokePoint(
    x: p.dx,
    y: p.dy,
    pressure: event.pressure > 0.0 ? event.pressure : 1.0,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );

  void _handlePointerDown(
    Offset point,
    PointerDownEvent event,
    Rect? selectedBounds,
  ) {
    final state = ref.read(whiteboardControllerProvider);
    final notifier = ref.read(whiteboardControllerProvider.notifier);
    final tool = state.currentTool;

    if (tool.isDrawingTool) {
      _gesture.points
        ..clear()
        ..add(_point(point, event));
      _gesture.changed();
    } else if (tool.isEraser) {
      notifier.beginEraseGesture();
      notifier.eraseAlong(point, point);
      _lastErasePoint = point;
      _gesture.eraser = point;
      _gesture.changed();
    } else if (tool == ToolType.shape) {
      _gesture.shapeStart = point;
      _gesture.shapeEnd = point;
      _gesture.changed();
    } else if (tool == ToolType.laser) {
      _gesture.laser = point;
      _gesture.changed();
    } else if (tool == ToolType.select) {
      final additive = HardwareKeyboard.instance.isShiftPressed;
      if (!additive &&
          selectedBounds != null &&
          selectedBounds.contains(point)) {
        _isPressingSelection = true;
        _dragStart = point;
      } else {
        final hitId = _findObjectAt(point);
        if (hitId != null) {
          if (additive) {
            final next = Set.of(state.selectedObjectIds);
            if (!next.remove(hitId)) next.add(hitId);
            notifier.setSelectedObjects(next);
          } else {
            notifier.setSelectedObjects({hitId});
            _isPressingSelection = true;
            _dragStart = point;
          }
        } else {
          if (!additive) notifier.setSelectedObjects({});
          _gesture.marquee = Rect.fromPoints(point, point);
          _gesture.changed();
        }
      }
    }
  }

  void _handlePointerMove(Offset point, PointerMoveEvent event) {
    final tool = ref.read(whiteboardControllerProvider).currentTool;

    if (tool.isDrawingTool) {
      if (_gesture.points.isEmpty) return;
      final last = _gesture.points.last;
      // Skip sub-pixel jitter: keeps stroke data lean without visible loss.
      if ((last.x - point.dx).abs() < 0.35 && (last.y - point.dy).abs() < 0.35) {
        return;
      }
      _gesture.points.add(_point(point, event));
      _gesture.changed();
    } else if (tool.isEraser) {
      final from = _lastErasePoint ?? point;
      ref.read(whiteboardControllerProvider.notifier).eraseAlong(from, point);
      _lastErasePoint = point;
      _gesture.eraser = point;
      _gesture.changed();
    } else if (tool == ToolType.shape) {
      _gesture.shapeEnd = point;
      _gesture.changed();
    } else if (tool == ToolType.laser) {
      _gesture.laser = point;
      _gesture.changed();
    } else if (tool == ToolType.select) {
      if (_isPressingSelection && _dragStart != null) {
        final delta = point - _dragStart!;
        if (!_isMovingSelected && delta.distance > 2.0) {
          setState(() => _isMovingSelected = true);
        }
        if (_isMovingSelected) {
          _gesture.dragOffset = delta;
          _gesture.changed();
        }
      } else if (_gesture.marquee != null) {
        _gesture.marquee = Rect.fromPoints(_gesture.marquee!.topLeft, point);
        _gesture.changed();
      }
    }
  }

  void _handlePointerUp(Offset point) {
    final state = ref.read(whiteboardControllerProvider);
    final notifier = ref.read(whiteboardControllerProvider.notifier);
    const uuid = Uuid();
    final tool = state.currentTool;

    if (tool.isDrawingTool) {
      if (_gesture.points.isNotEmpty) {
        final stroke = Stroke(
          id: uuid.v4(),
          points: List.of(_gesture.points),
          colorValue: state.selectedColorValue,
          width: state.selectedStrokeWidth,
          opacity: tool == ToolType.highlighter
              ? 0.35
              : (tool == ToolType.pencil ? 0.7 : 1.0),
          toolType: tool,
        );
        notifier.addStroke(stroke);
      }
      _gesture.points.clear();
      _gesture.changed();
    } else if (tool.isEraser) {
      notifier.endEraseGesture();
      _lastErasePoint = null;
      _gesture.eraser = null;
      _gesture.changed();
    } else if (tool == ToolType.shape) {
      final start = _gesture.shapeStart, end = _gesture.shapeEnd;
      if (start != null && end != null && (end - start).distance > 5.0) {
        notifier.addShape(
          ShapeObject(
            id: uuid.v4(),
            shapeType: state.selectedShapeType,
            start: start,
            end: end,
            strokeColorValue: state.selectedColorValue,
            strokeWidth: state.selectedStrokeWidth,
            fillColorValue: state.isShapeFilled
                ? state.selectedColor.withValues(alpha: 0.25).toARGB32()
                : null,
            isFilled: state.isShapeFilled,
          ),
        );
      }
      _gesture.shapeStart = null;
      _gesture.shapeEnd = null;
      _gesture.changed();
    } else if (tool == ToolType.text) {
      final existing = _findTextAt(point);
      _showTextDialog(position: point, existing: existing);
    } else if (tool == ToolType.laser) {
      _gesture.laser = null;
      _gesture.changed();
    } else if (tool == ToolType.select) {
      if (_gesture.marquee != null) {
        final inMarquee = _findObjectsInsideMarquee(_gesture.marquee!);
        final additive = HardwareKeyboard.instance.isShiftPressed;
        notifier.setSelectedObjects(
          additive ? {...state.selectedObjectIds, ...inMarquee} : inMarquee,
        );
        _gesture.marquee = null;
      }
      if (_isMovingSelected) {
        // One undoable move for the whole drag.
        notifier.translateSelected(_gesture.dragOffset);
        setState(() => _isMovingSelected = false);
      } else if (_isPressingSelection) {
        _maybeEditOnDoubleTap(point);
      }
      _gesture.dragOffset = Offset.zero;
      _isPressingSelection = false;
      _dragStart = null;
      _gesture.changed();
    }
  }

  void _maybeEditOnDoubleTap(Offset point) {
    final text = _findTextAt(point);
    final now = DateTime.now();
    if (text != null &&
        text.id == _lastTapTextId &&
        _lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 400) {
      _lastTapTextId = null;
      _showTextDialog(position: text.position, existing: text);
      return;
    }
    _lastTapTextId = text?.id;
    _lastTapTime = now;
  }

  TextObject? _findTextAt(Offset point) {
    final page = ref.read(whiteboardControllerProvider).project.currentPage;
    for (final text in page.texts.reversed) {
      if (text.hitTest(point)) return text;
    }
    return null;
  }

  String? _findObjectAt(Offset point) {
    final currentPage = ref
        .read(whiteboardControllerProvider)
        .project
        .currentPage;
    for (final text in currentPage.texts.reversed) {
      if (text.hitTest(point)) return text.id;
    }
    for (final stroke in currentPage.strokes.reversed) {
      if (stroke.hitTest(point, threshold: 12.0)) return stroke.id;
    }
    for (final shape in currentPage.shapes.reversed) {
      if (shape.hitTest(point)) return shape.id;
    }
    for (final plot in currentPage.plots.reversed) {
      if (plot.rect.contains(point)) return plot.id;
    }
    return null;
  }

  Set<String> _findObjectsInsideMarquee(Rect marquee) {
    final currentPage = ref
        .read(whiteboardControllerProvider)
        .project
        .currentPage;
    final ids = <String>{};
    for (final text in currentPage.texts) {
      if (marquee.overlaps(text.bounds)) ids.add(text.id);
    }
    for (final shape in currentPage.shapes) {
      if (marquee.overlaps(shape.bounds)) ids.add(shape.id);
    }
    for (final stroke in currentPage.strokes) {
      if (marquee.overlaps(stroke.bounds)) ids.add(stroke.id);
    }
    for (final plot in currentPage.plots) {
      if (marquee.overlaps(plot.rect)) ids.add(plot.id);
    }
    return ids;
  }

  Future<void> _showTextDialog({
    required Offset position,
    TextObject? existing,
  }) async {
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => _TextEditDialog(
        initialText: existing?.text ?? '',
        isEdit: existing != null,
      ),
    );
    if (content == null || !mounted) return; // cancelled
    final notifier = ref.read(whiteboardControllerProvider.notifier);
    if (existing != null) {
      if (content.isEmpty) {
        notifier.setSelectedObjects({existing.id});
        notifier.deleteSelected();
      } else if (content != existing.text) {
        notifier.updateText(existing, existing.copyWith(text: content));
      }
    } else if (content.isNotEmpty) {
      final state = ref.read(whiteboardControllerProvider);
      notifier.addText(
        TextObject(
          id: const Uuid().v4(),
          text: content,
          position: position,
          fontSize: state.selectedFontSize,
          colorValue: state.selectedColorValue,
        ),
      );
    }
  }
}

/// Add / edit text dialog. Owns its controller so it is disposed only after
/// the dialog's exit animation finishes.
class _TextEditDialog extends StatefulWidget {
  final String initialText;
  final bool isEdit;
  const _TextEditDialog({required this.initialText, required this.isEdit});

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEdit ? 'Edit Text' : 'Add Text Note'),
      content: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
        },
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Type lesson note or equation...',
            helperText: widget.isEdit
                ? 'Clear the text to delete it. Ctrl+Enter to save.'
                : 'Ctrl+Enter to add.',
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.isEdit ? 'Save' : 'Add to Board'),
        ),
      ],
    );
  }
}

/// An imported PDF page drawn at its place on the board, scaling with zoom.
/// Pages are rendered on first view (a white page with a small spinner shows
/// meanwhile; drawing works throughout), and the neighbouring pages are
/// prefetched so flipping pages is instant.
class _PdfPageImage extends StatefulWidget {
  final PdfPageAttachment pdf;
  final List<PdfPageAttachment> neighbours;
  const _PdfPageImage({super.key, required this.pdf, this.neighbours = const []});

  @override
  State<_PdfPageImage> createState() => _PdfPageImageState();
}

class _PdfPageImageState extends State<_PdfPageImage> {
  String? _path;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PdfPageImage old) {
    super.didUpdateWidget(old);
    if (old.pdf.imagePath != widget.pdf.imagePath) _load();
  }

  void _load() {
    final renderer = PdfPageRenderer.instance;
    _failed = false;
    _path = renderer.cachedImagePath(widget.pdf);
    if (_path == null) {
      final target = widget.pdf.imagePath;
      renderer.ensureImage(widget.pdf).then((path) {
        if (!mounted || widget.pdf.imagePath != target) return;
        setState(() {
          _path = path;
          _failed = path == null;
        });
        renderer.prefetch(widget.neighbours);
      });
    } else {
      renderer.prefetch(widget.neighbours);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pdf = widget.pdf;
    Widget message(String text) => Container(
          color: Colors.white,
          alignment: Alignment.center,
          child: Text(text, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 18)),
        );
    final Widget child;
    if (_path != null) {
      child = Image.file(
        File(_path!),
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => message('PDF page ${pdf.pageIndex + 1} could not be loaded'),
      );
    } else if (_failed) {
      child = message('PDF page ${pdf.pageIndex + 1} could not be loaded');
    } else {
      child = Container(
        color: Colors.white,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 40),
        child: const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    return Positioned.fromRect(
      rect: pdf.rect,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Paints in-progress ink, shape previews, eraser and laser cursors.
/// Repaints from [_LiveGesture] notifications without widget rebuilds.
class _LiveGesturePainter extends CustomPainter {
  final _LiveGesture gesture;
  final ToolType tool;
  final Color color;
  final double width;
  final ShapeType shapeType;
  final bool filled;

  _LiveGesturePainter({
    required this.gesture,
    required this.tool,
    required this.color,
    required this.width,
    required this.shapeType,
    required this.filled,
  }) : super(repaint: gesture);

  @override
  void paint(Canvas canvas, Size size) {
    ActiveStrokePainter(
      activePoints: gesture.points.isNotEmpty ? gesture.points : null,
      toolType: tool,
      color: color,
      width: width,
      opacity: tool == ToolType.highlighter
          ? 0.35
          : (tool == ToolType.pencil ? 0.7 : 1.0),
      activeShapeType: tool == ToolType.shape ? shapeType : null,
      shapeStart: gesture.shapeStart,
      shapeEnd: gesture.shapeEnd,
      isShapeFilled: filled,
      eraserPosition: gesture.eraser,
      eraserRadius: WhiteboardNotifier.eraserRadius,
      laserPosition: gesture.laser,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _LiveGesturePainter old) =>
      old.tool != tool ||
      old.color != color ||
      old.width != width ||
      old.shapeType != shapeType ||
      old.filled != filled ||
      !identical(old.gesture, gesture);
}

class _LiveSelectionPainter extends CustomPainter {
  final _LiveGesture gesture;
  final Rect? bounds;
  final bool isDragging;

  _LiveSelectionPainter({
    required this.gesture,
    required this.bounds,
    required this.isDragging,
  }) : super(repaint: gesture);

  @override
  void paint(Canvas canvas, Size size) {
    SelectionPainter(
      selectionMarquee: gesture.marquee,
      boundingBox: bounds?.shift(gesture.dragOffset),
      isDragging: isDragging,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _LiveSelectionPainter old) =>
      old.bounds != bounds || old.isDragging != isDragging;
}

/// Paints the selected elements at the current drag offset while the
/// originals are hidden, so dragging never rewrites the page per frame.
class _DragPreviewPainter extends CustomPainter {
  final _LiveGesture gesture;
  final List<Stroke> strokes;
  final List<ShapeObject> shapes;
  final List<TextObject> texts;

  _DragPreviewPainter({
    required this.gesture,
    required PageModel page,
    required Set<String> ids,
  }) : strokes = page.strokes.where((e) => ids.contains(e.id)).toList(),
       shapes = page.shapes.where((e) => ids.contains(e.id)).toList(),
       texts = page.texts.where((e) => ids.contains(e.id)).toList(),
       super(repaint: gesture);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(gesture.dragOffset.dx, gesture.dragOffset.dy);
    BoardPainter.paintElements(
      canvas,
      strokes: strokes,
      shapes: shapes,
      texts: texts,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DragPreviewPainter old) => true;
}
