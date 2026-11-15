import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/shape_model.dart';
import '../models/text_model.dart';
import '../models/tool_type.dart';

enum DiagramKind { flowchart, mindmap, concept }

class DiagramNode {
  final String id;
  final String label;
  final ShapeType shape; // rectangle, diamond (decision), circle (start/end)
  const DiagramNode(this.id, this.label, this.shape);
}

class DiagramEdge {
  final String from;
  final String to;
  final String? label;
  const DiagramEdge(this.from, this.to, [this.label]);
}

class DiagramSpec {
  final DiagramKind kind;
  final String title;
  final List<DiagramNode> nodes;
  final List<DiagramEdge> edges;
  const DiagramSpec({
    required this.kind,
    required this.title,
    required this.nodes,
    required this.edges,
  });

  /// JSON contract the model is asked to produce.
  static const String schemaPrompt =
      'Respond ONLY with a JSON object, no markdown, in this exact shape:\n'
      '{"title": "short title", "nodes": [{"id": "n1", "label": "short label (max 6 words)", "shape": "rectangle|diamond|circle"}], '
      '"edges": [{"from": "n1", "to": "n2", "label": "optional short label"}]}\n'
      'Rules: 3-14 nodes; ids unique; every edge references existing ids; use "diamond" only for yes/no decisions '
      'and "circle" only for start/end; labels must be factually correct and concise.';

  /// Parses model output, tolerating code fences or surrounding prose.
  /// Throws [FormatException] if no usable diagram is present.
  static DiagramSpec parse(String content, DiagramKind kind) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('No JSON object in response');
    }
    final data = jsonDecode(content.substring(start, end + 1));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Diagram is not an object');
    }

    final nodes = <DiagramNode>[];
    final seen = <String>{};
    for (final raw in (data['nodes'] as List<dynamic>? ?? const [])) {
      if (raw is! Map) continue;
      final id = raw['id']?.toString().trim() ?? '';
      final label = raw['label']?.toString().trim() ?? '';
      if (id.isEmpty || label.isEmpty || !seen.add(id)) continue;
      final shape = switch (raw['shape']?.toString().toLowerCase()) {
        'diamond' => ShapeType.diamond,
        'circle' || 'oval' || 'ellipse' => ShapeType.circle,
        _ => ShapeType.rectangle,
      };
      nodes.add(
        DiagramNode(
          id,
          label.length > 80 ? '${label.substring(0, 77)}...' : label,
          shape,
        ),
      );
      if (nodes.length >= 30) break; // keep the board readable
    }
    if (nodes.isEmpty) throw const FormatException('Diagram has no nodes');

    final edges = <DiagramEdge>[];
    for (final raw in (data['edges'] as List<dynamic>? ?? const [])) {
      if (raw is! Map) continue;
      final from = raw['from']?.toString().trim() ?? '';
      final to = raw['to']?.toString().trim() ?? '';
      if (!seen.contains(from) || !seen.contains(to) || from == to) continue;
      final label = raw['label']?.toString().trim();
      edges.add(
        DiagramEdge(from, to, (label == null || label.isEmpty) ? null : label),
      );
    }
    return DiagramSpec(
      kind: kind,
      title: data['title']?.toString().trim() ?? '',
      nodes: nodes,
      edges: edges,
    );
  }
}

/// Native, editable board elements produced from a [DiagramSpec].
class DiagramElements {
  final List<ShapeObject> shapes;
  final List<TextObject> texts;
  const DiagramElements(this.shapes, this.texts);
}

/// Lays out a diagram as ordinary shapes, arrows and text so teachers and
/// students can move, recolour, edit or erase any part of it.
class DiagramBuilder {
  static const double _fontSize = 18;
  static const double _hGap = 56;
  static const double _vGap = 72;
  static const _uuid = Uuid();

  static Size _measure(String text, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: _fontSize, fontFamily: 'Roboto'),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth);
    return tp.size;
  }

  static Size _nodeSize(DiagramNode n) {
    final t = _measure(n.label, 200);
    switch (n.shape) {
      case ShapeType.diamond:
        return Size(t.width * 1.9 + 40, t.height * 2.2 + 40);
      case ShapeType.circle:
        final d = math.max(t.width, t.height) * 1.3 + 36;
        return Size(d * 1.25, d * 0.8);
      default:
        return Size(t.width + 40, t.height + 28);
    }
  }

  /// Builds elements with the diagram's top-left corner at [origin].
  static DiagramElements build(
    DiagramSpec spec, {
    required Offset origin,
    int colorValue = 0xFF1E3A8A,
  }) {
    final sizes = {for (final n in spec.nodes) n.id: _nodeSize(n)};
    final centers = spec.kind == DiagramKind.flowchart
        ? _layeredLayout(spec, sizes)
        : _radialLayout(spec, sizes);

    // Normalise so the diagram's bounding box starts at origin (+ title).
    double minX = double.infinity, minY = double.infinity;
    for (final n in spec.nodes) {
      final c = centers[n.id]!, s = sizes[n.id]!;
      minX = math.min(minX, c.dx - s.width / 2);
      minY = math.min(minY, c.dy - s.height / 2);
    }
    final titleSpace = spec.title.isEmpty ? 0.0 : 48.0;
    final shift = origin - Offset(minX, minY) + Offset(0, titleSpace);
    final placed = {for (final e in centers.entries) e.key: e.value + shift};

    final shapes = <ShapeObject>[];
    final texts = <TextObject>[];
    final rects = <String, Rect>{};

    if (spec.title.isNotEmpty) {
      texts.add(
        TextObject(
          id: _uuid.v4(),
          text: spec.title,
          position: origin,
          fontSize: 24,
          colorValue: colorValue,
          isBold: true,
        ),
      );
    }

    for (final n in spec.nodes) {
      final rect = Rect.fromCenter(
        center: placed[n.id]!,
        width: sizes[n.id]!.width,
        height: sizes[n.id]!.height,
      );
      rects[n.id] = rect;
      shapes.add(
        ShapeObject(
          id: _uuid.v4(),
          shapeType: n.shape,
          start: rect.topLeft,
          end: rect.bottomRight,
          strokeColorValue: colorValue,
          strokeWidth: 2.5,
          fillColorValue: Color(colorValue).withValues(alpha: 0.08).toARGB32(),
          isFilled: true,
        ),
      );
      final ts = _measure(n.label, 200);
      texts.add(
        TextObject(
          id: _uuid.v4(),
          text: _wrap(n.label, 200),
          position: rect.center - Offset(ts.width / 2, ts.height / 2),
          fontSize: _fontSize,
          colorValue: 0xFF111827,
        ),
      );
    }

    for (final e in spec.edges) {
      final a = rects[e.from]!, b = rects[e.to]!;
      final start = _edgePoint(a, b.center);
      final end = _edgePoint(b, a.center);
      if ((end - start).distance < 4) continue;
      shapes.add(
        ShapeObject(
          id: _uuid.v4(),
          shapeType: ShapeType.arrow,
          start: start,
          end: end,
          strokeColorValue: 0xFF374151,
          strokeWidth: 2.0,
        ),
      );
      if (e.label != null) {
        final mid = Offset.lerp(start, end, 0.5)!;
        texts.add(
          TextObject(
            id: _uuid.v4(),
            text: e.label!,
            position: mid + const Offset(6, -22),
            fontSize: 14,
            colorValue: 0xFF6B7280,
            isItalic: true,
          ),
        );
      }
    }
    return DiagramElements(shapes, texts);
  }

  /// Inserts explicit line breaks so board text (laid out without a width)
  /// wraps the same way it was measured.
  static String _wrap(String text, double maxWidth) {
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var line = '';
    for (final w in words) {
      final candidate = line.isEmpty ? w : '$line $w';
      if (line.isNotEmpty &&
          _measure(candidate, double.infinity).width > maxWidth) {
        lines.add(line);
        line = w;
      } else {
        line = candidate;
      }
    }
    if (line.isNotEmpty) lines.add(line);
    return lines.join('\n');
  }

  /// Point where the segment from rect centre toward [target] leaves [r].
  static Offset _edgePoint(Rect r, Offset target) {
    final c = r.center;
    final d = target - c;
    if (d == Offset.zero) return c;
    final sx = d.dx == 0 ? double.infinity : (r.width / 2) / d.dx.abs();
    final sy = d.dy == 0 ? double.infinity : (r.height / 2) / d.dy.abs();
    final t = math.min(sx, sy);
    return c + d * (t + 6 / d.distance); // small gap so arrows don't touch
  }

  /// Top-down layered layout (longest path from roots; cycles tolerated).
  static Map<String, Offset> _layeredLayout(
    DiagramSpec spec,
    Map<String, Size> sizes,
  ) {
    final ids = spec.nodes.map((n) => n.id).toList();
    final incoming = {for (final id in ids) id: 0};
    final out = {for (final id in ids) id: <String>[]};
    for (final e in spec.edges) {
      incoming[e.to] = incoming[e.to]! + 1;
      out[e.from]!.add(e.to);
    }
    final layer = <String, int>{};
    var roots = ids.where((id) => incoming[id] == 0).toList();
    if (roots.isEmpty) roots = [ids.first];
    final queue = <String>[...roots];
    for (final r in roots) {
      layer[r] = 0;
    }
    int guard = 0;
    while (queue.isNotEmpty && guard++ < 10000) {
      final id = queue.removeAt(0);
      for (final nxt in out[id]!) {
        final cand = layer[id]! + 1;
        if (cand < ids.length && (layer[nxt] == null || layer[nxt]! < cand)) {
          layer[nxt] = cand;
          queue.add(nxt);
        }
      }
    }
    int maxLayer = layer.values.fold(0, math.max);
    for (final id in ids) {
      layer[id] ??= ++maxLayer; // disconnected nodes go underneath
    }

    final byLayer = <int, List<String>>{};
    for (final id in ids) {
      byLayer.putIfAbsent(layer[id]!, () => []).add(id);
    }
    final centers = <String, Offset>{};
    double y = 0;
    for (final l in byLayer.keys.toList()..sort()) {
      final row = byLayer[l]!;
      final rowH = row.map((id) => sizes[id]!.height).fold(0.0, math.max);
      final rowW =
          row.map((id) => sizes[id]!.width).fold(0.0, (a, b) => a + b) +
          _hGap * (row.length - 1);
      double x = -rowW / 2;
      for (final id in row) {
        final w = sizes[id]!.width;
        centers[id] = Offset(x + w / 2, y + rowH / 2);
        x += w + _hGap;
      }
      y += rowH + _vGap;
    }
    return centers;
  }

  /// Radial layout for mind maps / concept maps: hub in the centre, first
  /// ring for its neighbours, outer ring for the rest.
  static Map<String, Offset> _radialLayout(
    DiagramSpec spec,
    Map<String, Size> sizes,
  ) {
    final ids = spec.nodes.map((n) => n.id).toList();
    final degree = {for (final id in ids) id: 0};
    for (final e in spec.edges) {
      degree[e.from] = degree[e.from]! + 1;
      degree[e.to] = degree[e.to]! + 1;
    }
    final hub = ids.reduce((a, b) => degree[b]! > degree[a]! ? b : a);
    final neighbours = <String>{
      for (final e in spec.edges)
        if (e.from == hub) e.to else if (e.to == hub) e.from,
    }.toList();
    final rest = ids
        .where((id) => id != hub && !neighbours.contains(id))
        .toList();

    final maxW = sizes.values.map((s) => s.width).fold(0.0, math.max);
    final r1 = math.max(
      220.0,
      (neighbours.length * (maxW + 24)) / (2 * math.pi),
    );
    final r2 = r1 + maxW + 80;

    final centers = <String, Offset>{hub: Offset.zero};
    for (int i = 0; i < neighbours.length; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / neighbours.length;
      centers[neighbours[i]] = Offset(
        math.cos(a) * r1 * 1.25,
        math.sin(a) * r1,
      );
    }
    // Place outer nodes near the neighbour they connect to.
    final placedAngles = <String, double>{};
    for (int i = 0; i < neighbours.length; i++) {
      placedAngles[neighbours[i]] =
          -math.pi / 2 + 2 * math.pi * i / neighbours.length;
    }
    final perParent = <String, int>{};
    for (int i = 0; i < rest.length; i++) {
      final id = rest[i];
      String? parent;
      for (final e in spec.edges) {
        if (e.from == id && placedAngles.containsKey(e.to)) parent = e.to;
        if (e.to == id && placedAngles.containsKey(e.from)) parent = e.from;
      }
      double angle;
      if (parent != null) {
        final k = perParent[parent] = (perParent[parent] ?? 0) + 1;
        angle =
            placedAngles[parent]! + (k.isOdd ? 1 : -1) * 0.28 * ((k + 1) ~/ 2);
      } else {
        angle = -math.pi / 2 + 2 * math.pi * i / math.max(1, rest.length) + 0.3;
      }
      placedAngles[id] = angle;
      centers[id] = Offset(math.cos(angle) * r2 * 1.25, math.sin(angle) * r2);
    }
    return centers;
  }
}
