import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
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

class WhiteboardCanvas extends ConsumerStatefulWidget {
  const WhiteboardCanvas({super.key});

  @override
  ConsumerState<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends ConsumerState<WhiteboardCanvas> {
  final TransformationController _transformController =
      TransformationController();

  // Active gesture tracking
  final List<StrokePoint> _activePoints = [];
  Offset? _shapeStart;
  Offset? _shapeEnd;
  Offset? _eraserPoint;
  Offset? _laserPoint;

  // Selection tracking
  Rect? _selectionMarquee;
  Offset? _dragStart;
  bool _isMovingSelected = false;

  final Set<int> _activePointers = {};

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    ref.read(whiteboardControllerProvider.notifier).setZoomAndPan(
      scale,
      Offset(
        _transformController.value.entry(0, 3),
        _transformController.value.entry(1, 3),
      ),
    );
  }

  void _zoomBy(double factor) {
    final matrix = _transformController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final isInfinite = ref.read(whiteboardControllerProvider).isInfiniteCanvas;
    final minScale = isInfinite ? 0.1 : 0.4;
    final maxScale = isInfinite ? 6.0 : 3.5;
    final targetScale = (currentScale * factor).clamp(minScale, maxScale);
    final actualFactor = targetScale / currentScale;

    final renderBox = context.findRenderObject() as RenderBox?;
    final center = renderBox != null
        ? renderBox.size.center(Offset.zero)
        : const Offset(400, 600);

    matrix.translate(center.dx, center.dy);
    matrix.scale(actualFactor);
    matrix.translate(-center.dx, -center.dy);
    _transformController.value = matrix;
  }

  void _resetTransform() {
    _transformController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  Offset _screenToCanvas(Offset screenOffset) {
    return _transformController.toScene(screenOffset);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardControllerProvider);
    final currentPage = state.project.currentPage;
    final isInfinite = state.isInfiniteCanvas;

    // Listen for zoom actions from floating zoom toolbar
    ref.listen<CanvasZoomAction>(canvasZoomActionProvider, (prev, next) {
      if (next == CanvasZoomAction.zoomIn) {
        _zoomBy(1.25);
        ref.read(canvasZoomActionProvider.notifier).reset();
      } else if (next == CanvasZoomAction.zoomOut) {
        _zoomBy(0.80);
        ref.read(canvasZoomActionProvider.notifier).reset();
      } else if (next == CanvasZoomAction.reset) {
        _resetTransform();
        ref.read(canvasZoomActionProvider.notifier).reset();
      }
    });

    // Calculate bounding box for selected elements if any
    Rect? selectedBounds;
    if (state.selectedObjectIds.isNotEmpty) {
      final selectedStrokes = currentPage.strokes
          .where((s) => state.selectedObjectIds.contains(s.id));
      final selectedShapes = currentPage.shapes
          .where((s) => state.selectedObjectIds.contains(s.id));
      final selectedTexts = currentPage.texts
          .where((t) => state.selectedObjectIds.contains(t.id));

      for (final s in selectedStrokes) {
        selectedBounds = selectedBounds == null
            ? s.bounds
            : selectedBounds.expandToInclude(s.bounds);
      }
      for (final s in selectedShapes) {
        selectedBounds = selectedBounds == null
            ? s.bounds
            : selectedBounds.expandToInclude(s.bounds);
      }
      for (final t in selectedTexts) {
        selectedBounds = selectedBounds == null
            ? t.bounds
            : selectedBounds.expandToInclude(t.bounds);
      }
    }

    final isTwoFinger = _activePointers.length >= 2;

    return Stack(
      children: [
        // Layer 0: Seamless Full-Screen Background Surface (Infinite Canvas or Paginated Desk + Sheet)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _transformController,
            builder: (context, _) {
              return CustomPaint(
                painter: BackgroundPainter(
                  background: currentPage.background,
                  isInfiniteCanvas: isInfinite,
                  transform: _transformController.value,
                ),
              );
            },
          ),
        ),

        // Layer 1: Interactive Canvas Content & Stylus Gestures
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _transformController,
            boundaryMargin: isInfinite
                ? const EdgeInsets.all(50000)
                : const EdgeInsets.symmetric(horizontal: 1000, vertical: 1200),
            minScale: isInfinite ? 0.10 : 0.40,
            maxScale: isInfinite ? 6.0 : 3.5,
            panEnabled: isTwoFinger,
            scaleEnabled: isTwoFinger,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                _activePointers.add(event.pointer);
                if (_activePointers.length >= 2) {
                  // Cancel drawing if second finger lands
                  setState(() {
                    _activePoints.clear();
                    _shapeStart = null;
                    _shapeEnd = null;
                    _eraserPoint = null;
                    _laserPoint = null;
                    _selectionMarquee = null;
                  });
                  return;
                }

                final canvasPoint = _screenToCanvas(event.localPosition);
                _handlePointerDown(canvasPoint, event, selectedBounds);
              },
              onPointerMove: (event) {
                if (_activePointers.length >= 2) return;
                final canvasPoint = _screenToCanvas(event.localPosition);
                _handlePointerMove(canvasPoint, event);
              },
              onPointerUp: (event) {
                _activePointers.remove(event.pointer);
                if (_activePointers.isNotEmpty) return;
                final canvasPoint = _screenToCanvas(event.localPosition);
                _handlePointerUp(canvasPoint);
              },
              onPointerCancel: (event) {
                _activePointers.remove(event.pointer);
                setState(() {
                  _activePoints.clear();
                  _shapeStart = null;
                  _shapeEnd = null;
                  _eraserPoint = null;
                  _laserPoint = null;
                  _selectionMarquee = null;
                });
              },
              child: Stack(
                children: [
                  // Layer 1: Committed Board Content (Strokes, Shapes, Texts)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: BoardPainter(
                    strokes: currentPage.strokes,
                    shapes: currentPage.shapes,
                    texts: currentPage.texts,
                    selectedIds: state.selectedObjectIds,
                  ),
                ),
              ),
            ),

            // Layer 3: Selection Bounding Box & Marquee
            if (state.currentTool == ToolType.select)
              Positioned.fill(
                child: CustomPaint(
                  painter: SelectionPainter(
                    selectionMarquee: _selectionMarquee,
                    boundingBox: selectedBounds,
                    isDragging: _isMovingSelected,
                  ),
                ),
              ),

            // Layer 4: Active Stroke / Gesture in progress
            Positioned.fill(
              child: CustomPaint(
                painter: ActiveStrokePainter(
                  activePoints: _activePoints.isNotEmpty ? _activePoints : null,
                  toolType: state.currentTool,
                  color: state.selectedColor,
                  width: state.selectedStrokeWidth,
                  opacity: state.currentTool == ToolType.highlighter
                      ? 0.35
                      : (state.currentTool == ToolType.pencil ? 0.7 : 1.0),
                  activeShapeType: state.currentTool == ToolType.shape
                      ? state.selectedShapeType
                      : null,
                  shapeStart: _shapeStart,
                  shapeEnd: _shapeEnd,
                  isShapeFilled: state.isShapeFilled,
                  eraserPosition: _eraserPoint,
                  laserPosition: _laserPoint,
                ),
              ),
            ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handlePointerDown(
    Offset point,
    PointerDownEvent event,
    Rect? selectedBounds,
  ) {
    final state = ref.read(whiteboardControllerProvider);

    if (state.currentTool.isDrawingTool) {
      setState(() {
        _activePoints.clear();
        _activePoints.add(StrokePoint(
          x: point.dx,
          y: point.dy,
          pressure: event.pressure > 0.0 ? event.pressure : 1.0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
      });
    } else if (state.currentTool.isEraser) {
      setState(() {
        _eraserPoint = point;
      });
      ref.read(whiteboardControllerProvider.notifier).eraseAtPoint(point);
    } else if (state.currentTool == ToolType.shape) {
      setState(() {
        _shapeStart = point;
        _shapeEnd = point;
      });
    } else if (state.currentTool == ToolType.laser) {
      setState(() {
        _laserPoint = point;
      });
    } else if (state.currentTool == ToolType.select) {
      // Check if tap was inside existing selection bounds to start drag
      if (selectedBounds != null && selectedBounds.contains(point)) {
        _isMovingSelected = true;
        _dragStart = point;
      } else {
        // Direct tap hit-test or begin marquee
        final hitId = _findObjectAt(point);
        if (hitId != null) {
          ref
              .read(whiteboardControllerProvider.notifier)
              .setSelectedObjects({hitId});
          _isMovingSelected = true;
          _dragStart = point;
        } else {
          // Clear selection and start marquee
          ref
              .read(whiteboardControllerProvider.notifier)
              .setSelectedObjects({});
          setState(() {
            _selectionMarquee = Rect.fromPoints(point, point);
          });
        }
      }
    }
  }

  void _handlePointerMove(Offset point, PointerMoveEvent event) {
    final state = ref.read(whiteboardControllerProvider);

    if (state.currentTool.isDrawingTool) {
      setState(() {
        _activePoints.add(StrokePoint(
          x: point.dx,
          y: point.dy,
          pressure: event.pressure > 0.0 ? event.pressure : 1.0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
      });
    } else if (state.currentTool.isEraser) {
      setState(() {
        _eraserPoint = point;
      });
      ref.read(whiteboardControllerProvider.notifier).eraseAtPoint(point);
    } else if (state.currentTool == ToolType.shape) {
      setState(() {
        _shapeEnd = point;
      });
    } else if (state.currentTool == ToolType.laser) {
      setState(() {
        _laserPoint = point;
      });
    } else if (state.currentTool == ToolType.select) {
      if (_isMovingSelected && _dragStart != null) {
        final delta = point - _dragStart!;
        if (delta.distance > 1.0) {
          ref
              .read(whiteboardControllerProvider.notifier)
              .translateSelected(delta);
          _dragStart = point;
        }
      } else if (_selectionMarquee != null) {
        setState(() {
          _selectionMarquee =
              Rect.fromPoints(_selectionMarquee!.topLeft, point);
        });
      }
    }
  }

  void _handlePointerUp(Offset point) {
    final state = ref.read(whiteboardControllerProvider);
    const uuid = Uuid();

    if (state.currentTool.isDrawingTool) {
      if (_activePoints.isNotEmpty) {
        final stroke = Stroke(
          id: uuid.v4(),
          points: List.from(_activePoints),
          colorValue: state.selectedColorValue,
          width: state.selectedStrokeWidth,
          opacity: state.currentTool == ToolType.highlighter
              ? 0.35
              : (state.currentTool == ToolType.pencil ? 0.7 : 1.0),
          toolType: state.currentTool,
        );
        ref.read(whiteboardControllerProvider.notifier).addStroke(stroke);
      }
      setState(() {
        _activePoints.clear();
      });
    } else if (state.currentTool.isEraser) {
      setState(() {
        _eraserPoint = null;
      });
    } else if (state.currentTool == ToolType.shape) {
      if (_shapeStart != null && _shapeEnd != null) {
        final distance = (_shapeEnd! - _shapeStart!).distance;
        if (distance > 5.0) {
          final shape = ShapeObject(
            id: uuid.v4(),
            shapeType: state.selectedShapeType,
            start: _shapeStart!,
            end: _shapeEnd!,
            strokeColorValue: state.selectedColorValue,
            strokeWidth: state.selectedStrokeWidth,
            fillColorValue: state.isShapeFilled
                ? state.selectedColor.withValues(alpha: 0.25).toARGB32()
                : null,
            isFilled: state.isShapeFilled,
          );
          ref.read(whiteboardControllerProvider.notifier).addShape(shape);
        }
      }
      setState(() {
        _shapeStart = null;
        _shapeEnd = null;
      });
    } else if (state.currentTool == ToolType.text) {
      _showAddTextDialog(point);
    } else if (state.currentTool == ToolType.laser) {
      setState(() {
        _laserPoint = null;
      });
    } else if (state.currentTool == ToolType.select) {
      if (_selectionMarquee != null) {
        final selectedIds = _findObjectsInsideMarquee(_selectionMarquee!);
        ref
            .read(whiteboardControllerProvider.notifier)
            .setSelectedObjects(selectedIds);
      }
      setState(() {
        _selectionMarquee = null;
        _isMovingSelected = false;
        _dragStart = null;
      });
    }
  }

  String? _findObjectAt(Offset point) {
    final currentPage =
        ref.read(whiteboardControllerProvider).project.currentPage;

    // Check texts
    for (final text in currentPage.texts.reversed) {
      if (text.hitTest(point)) return text.id;
    }
    // Check shapes
    for (final shape in currentPage.shapes.reversed) {
      if (shape.hitTest(point)) return shape.id;
    }
    // Check strokes
    for (final stroke in currentPage.strokes.reversed) {
      if (stroke.hitTest(point, threshold: 12.0)) return stroke.id;
    }
    return null;
  }

  Set<String> _findObjectsInsideMarquee(Rect marquee) {
    final currentPage =
        ref.read(whiteboardControllerProvider).project.currentPage;
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
    return ids;
  }

  void _showAddTextDialog(Offset position) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add Text Note'),
          content: TextField(
            controller: textController,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Type lesson note or equation...',
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
                final content = textController.text.trim();
                if (content.isNotEmpty) {
                  final state = ref.read(whiteboardControllerProvider);
                  final textObj = TextObject(
                    id: const Uuid().v4(),
                    text: content,
                    position: position,
                    fontSize: state.selectedFontSize,
                    colorValue: state.selectedColorValue,
                  );
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .addText(textObj);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add to Board'),
            ),
          ],
        );
      },
    );
  }
}
