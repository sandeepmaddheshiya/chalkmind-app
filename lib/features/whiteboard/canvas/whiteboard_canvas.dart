import 'package:flutter/gestures.dart';
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

  // Robust pointer & palm rejection tracking
  int? _drawingPointerId;
  bool _isDrawingWithStylus = false;
  DateTime? _drawingStartTime;
  final Map<int, Offset> _activePointers = {};
  Offset? _handPanLastPos;
  bool _twoFingerActive = false;
  double? _lastPinchDistance;
  Offset? _lastTwoFingerMidpoint;

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

  void _panBy(Offset screenDelta) {
    final matrix = _transformController.value.clone();
    final currentTx = matrix.entry(0, 3);
    final currentTy = matrix.entry(1, 3);
    matrix.setEntry(0, 3, currentTx + screenDelta.dx);
    matrix.setEntry(1, 3, currentTy + screenDelta.dy);
    _transformController.value = matrix;
  }

  void _zoomAround(Offset focalPoint, double factor, {required bool isInfinite}) {
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

    matrix.scale(actualRatio);
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
    super.dispose();
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
      } else if (next == CanvasZoomAction.panLeft) {
        _panBy(const Offset(300, 0));
        ref.read(canvasZoomActionProvider.notifier).reset();
      } else if (next == CanvasZoomAction.panRight) {
        _panBy(const Offset(-300, 0));
        ref.read(canvasZoomActionProvider.notifier).reset();
      } else if (next == CanvasZoomAction.panUp) {
        _panBy(const Offset(0, 300));
        ref.read(canvasZoomActionProvider.notifier).reset();
      } else if (next == CanvasZoomAction.panDown) {
        _panBy(const Offset(0, -300));
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

        // Layer 1: Interactive Canvas Content & Full-Screen Touch Surface (Zero Dead Zones)
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              final isStylus = event.kind == PointerDeviceKind.stylus ||
                  event.kind == PointerDeviceKind.invertedStylus;

              _activePointers[event.pointer] = event.position;

              // Hand / Pan Tool: Moving the infinite canvas
              if (state.currentTool == ToolType.hand) {
                if (_activePointers.length >= 2) {
                  final points = _activePointers.values.toList();
                  _lastTwoFingerMidpoint = (points[0] + points[1]) / 2;
                  _lastPinchDistance = (points[0] - points[1]).distance;
                  _twoFingerActive = true;
                } else {
                  _handPanLastPos = event.position;
                }
                return;
              }

              // Stylus takes absolute priority for drawing with 100% palm rejection
              if (isStylus) {
                if (_drawingPointerId != null && !_isDrawingWithStylus) {
                  setState(() {
                    _activePoints.clear();
                    _shapeStart = null;
                    _shapeEnd = null;
                    _eraserPoint = null;
                    _laserPoint = null;
                    _selectionMarquee = null;
                  });
                }
                _drawingPointerId = event.pointer;
                _isDrawingWithStylus = true;
                _drawingStartTime = DateTime.now();
                final canvasPoint = _toCanvasPoint(event.localPosition);
                _handlePointerDown(canvasPoint, event, selectedBounds);
                return;
              }

              // If currently drawing with stylus, ignore all touch inputs (palm rejection)
              if (_isDrawingWithStylus) {
                return;
              }

              // Touch drawing & multi-touch handling
              if (_drawingPointerId == null) {
                if (_activePointers.length >= 2) {
                  // Two or more fingers touched down: Start 2-finger pan & pinch zoom
                  final points = _activePointers.values.toList();
                  _lastTwoFingerMidpoint = (points[0] + points[1]) / 2;
                  _lastPinchDistance = (points[0] - points[1]).distance;
                  _twoFingerActive = true;
                  return;
                }
                // Single finger touched down: Start drawing
                _drawingPointerId = event.pointer;
                _drawingStartTime = DateTime.now();
                final canvasPoint = _toCanvasPoint(event.localPosition);
                _handlePointerDown(canvasPoint, event, selectedBounds);
              } else {
                // Another contact occurred while already drawing
                // Check if this was a simultaneous 2-finger tap/gesture (< 120ms and <= 2 points)
                final elapsed = _drawingStartTime != null
                    ? DateTime.now()
                        .difference(_drawingStartTime!)
                        .inMilliseconds
                    : 999;
                if (elapsed < 120 && _activePoints.length <= 2) {
                  // User intended a 2-finger pan/zoom gesture
                  _drawingPointerId = null;
                  setState(() {
                    _activePoints.clear();
                    _shapeStart = null;
                    _shapeEnd = null;
                    _eraserPoint = null;
                    _laserPoint = null;
                    _selectionMarquee = null;
                  });
                  final points = _activePointers.values.toList();
                  if (points.length >= 2) {
                    _lastTwoFingerMidpoint = (points[0] + points[1]) / 2;
                    _lastPinchDistance = (points[0] - points[1]).distance;
                    _twoFingerActive = true;
                  }
                } else {
                  // Stroke is already well underway: ignore secondary touch (palm contact)
                  // Do NOT cancel the in-progress stroke!
                }
              }
            },
            onPointerMove: (event) {
              _activePointers[event.pointer] = event.position;

              // If drawing with stylus, ignore non-stylus pointer moves
              if (_isDrawingWithStylus && event.pointer != _drawingPointerId) {
                return;
              }

              // 2-finger pan & pinch zoom (when active)
              if (_twoFingerActive && _activePointers.length >= 2) {
                final points = _activePointers.values.toList();
                final mid = (points[0] + points[1]) / 2;
                final dist = (points[0] - points[1]).distance;

                // Pan by midpoint movement
                if (_lastTwoFingerMidpoint != null) {
                  final delta = mid - _lastTwoFingerMidpoint!;
                  _panBy(delta);
                }
                _lastTwoFingerMidpoint = mid;

                // Pinch zoom around midpoint
                if (_lastPinchDistance != null &&
                    _lastPinchDistance! > 10 &&
                    dist > 10) {
                  final scaleDelta = dist / _lastPinchDistance!;
                  _zoomAround(mid, scaleDelta, isInfinite: isInfinite);
                }
                _lastPinchDistance = dist;
                return;
              }

              // Hand / Pan Tool: 1-finger drag to move canvas
              if (state.currentTool == ToolType.hand) {
                if (_handPanLastPos != null) {
                  final delta = event.position - _handPanLastPos!;
                  _panBy(delta);
                  _handPanLastPos = event.position;
                }
                return;
              }

              // Primary drawing pointer movement
              if (event.pointer == _drawingPointerId) {
                final canvasPoint = _toCanvasPoint(event.localPosition);
                _handlePointerMove(canvasPoint, event);
              }
            },
            onPointerUp: (event) {
              _activePointers.remove(event.pointer);

              if (_activePointers.length < 2) {
                _twoFingerActive = false;
                _lastTwoFingerMidpoint = null;
                _lastPinchDistance = null;
              }

              if (state.currentTool == ToolType.hand) {
                if (_activePointers.isEmpty) {
                  _handPanLastPos = null;
                }
                return;
              }

              if (event.pointer == _drawingPointerId) {
                final canvasPoint = _toCanvasPoint(event.localPosition);
                _handlePointerUp(canvasPoint);
                _drawingPointerId = null;
                _isDrawingWithStylus = false;
              }

              if (_activePointers.isEmpty) {
                _handPanLastPos = null;
                _twoFingerActive = false;
                _drawingPointerId = null;
                _isDrawingWithStylus = false;
              }
            },
            onPointerCancel: (event) {
              _activePointers.remove(event.pointer);

              if (_activePointers.length < 2) {
                _twoFingerActive = false;
                _lastTwoFingerMidpoint = null;
                _lastPinchDistance = null;
              }

              if (state.currentTool == ToolType.hand) {
                if (_activePointers.isEmpty) {
                  _handPanLastPos = null;
                }
                return;
              }

              if (event.pointer == _drawingPointerId) {
                // Commit completed stroke if substantial points were drawn
                if (_activePoints.length >= 2 &&
                    state.currentTool.isDrawingTool) {
                  final canvasPoint = _toCanvasPoint(event.localPosition);
                  _handlePointerUp(canvasPoint);
                } else {
                  setState(() {
                    _activePoints.clear();
                    _shapeStart = null;
                    _shapeEnd = null;
                    _eraserPoint = null;
                    _laserPoint = null;
                    _selectionMarquee = null;
                  });
                }
                _drawingPointerId = null;
                _isDrawingWithStylus = false;
              }

              if (_activePointers.isEmpty) {
                _handPanLastPos = null;
                _twoFingerActive = false;
                _drawingPointerId = null;
                _isDrawingWithStylus = false;
              }
            },
            child: AnimatedBuilder(
              animation: _transformController,
              builder: (context, _) {
                return ClipRect(
                  child: Transform(
                    transform: _transformController.value,
                    alignment: Alignment.topLeft,
                    child: SizedBox.expand(
                      child: Stack(
                        clipBehavior: Clip.none,
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
                                activePoints: _activePoints.isNotEmpty
                                    ? _activePoints
                                    : null,
                                toolType: state.currentTool,
                                color: state.selectedColor,
                                width: state.selectedStrokeWidth,
                                opacity: state.currentTool == ToolType.highlighter
                                    ? 0.35
                                    : (state.currentTool == ToolType.pencil
                                        ? 0.7
                                        : 1.0),
                                activeShapeType:
                                    state.currentTool == ToolType.shape
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
                );
              },
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
