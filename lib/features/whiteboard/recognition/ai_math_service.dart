import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../core/ai/ai_config.dart';
import '../../../core/ai/openrouter_client.dart';
import '../models/stroke_model.dart';
import 'handwriting_math_engine.dart';

class AiMathService {
  /// Solves mathematical expressions, equations, and geometry diagrams directly from strokes
  /// using multimodal vision intelligence via OpenRouter.
  ///
  /// Returns `null` when the image contains no solvable math. Throws
  /// [AiException] for configuration, auth, network, or provider failures so
  /// the UI can tell the user what went wrong.
  static Future<HandwritingMathResult?> solveWithVisionAI({
    required List<Stroke> strokes,
    required AiConfig config,
    AiCancelToken? cancelToken,
    bool interactive = true,
  }) async {
    if (strokes.isEmpty) return null;
    if (!config.isConfigured) {
      throw const AiException(AiErrorKind.notConfigured, 'Not signed in');
    }

    final base64Image = await renderStrokesToBase64Png(strokes);
    if (base64Image == null) return null;

    final content = await OpenRouterClient(config).complete(
      messages: [aiUserMessage(_promptText, base64Png: base64Image)],
      temperature: 0.1,
      maxTokens: 900,
      timeout: const Duration(seconds: 20),
      cancelToken: cancelToken,
      action: 'solve',
      interactive: interactive,
    );
    return parseAiResponse(content, strokes);
  }

  static const String _promptText =
      'You are an expert STEM tutor solving a problem handwritten on a classroom whiteboard. '
      'The image may contain mathematics (arithmetic, algebra, calculus, identities), geometry diagrams, '
      'physics problems, chemistry (equations to balance, reaction products, molar mass, stoichiometry, pH), '
      'or another science question. The writer usually ends with "=", "?", an arrow "→", or an unknown such as "x =".\n'
      'First transcribe every symbol, digit and label exactly, using all context in the image '
      '(diagram labels, right-angle marks, given values, units). Then solve it correctly.\n'
      'Examples of the required JSON:\n'
      'Algebraic identity: {"subject": "math", "expression": "a³ - b³ =", "answer": "(a - b)(a² + ab + b²)", '
      '"steps": ["Use u³ - v³ = (u - v)(u² + uv + v²)", "Set u = a, v = b"], "explanation": "Difference of cubes."}\n'
      'Geometry (right triangle, legs 3 and 4, hypotenuse x): {"subject": "geometry", "expression": "x = √(3² + 4²) =", '
      '"answer": "5", "steps": ["Pythagoras: a² + b² = c²", "9 + 16 = 25", "x = √25 = 5"], '
      '"explanation": "Hypotenuse² equals the sum of the squares of the legs."}\n'
      'Chemistry (balance H2 + O2 → H2O): {"subject": "chemistry", "expression": "H₂ + O₂ →", '
      '"answer": "2H₂ + O₂ → 2H₂O", "steps": ["Count atoms: H 2→2, O 2→1", "Put 2 before H₂O: O balanced, H now 4", '
      '"Put 2 before H₂: H balanced"], "explanation": "Atoms of each element must be equal on both sides."}\n'
      'Physics (v = 20 m/s, t = 5 s, a = ?): {"subject": "physics", "expression": "a = v / t =", "answer": "4 m/s²", '
      '"steps": ["a = Δv / Δt", "a = 20 / 5 = 4 m/s²"], "explanation": "Acceleration is the rate of change of velocity."}\n'
      'Rules:\n'
      '- Keep "answer" concise: the final value with units, the simplified expression, or the balanced equation. '
      'Use Unicode (², √, π, subscripts like H₂O, →) not LaTeX.\n'
      '- "steps" are short, numbered-order working a student can follow (max 6).\n'
      '- If several things are written, solve the one marked with "=", "?" or "→" that is still unanswered.\n'
      '- If you cannot read it confidently, set "answer" to your best reading but say so in "explanation".\n'
      '- If the image contains no question or problem at all, respond with {"expression": "", "answer": ""}.\n'
      'Respond ONLY with the JSON object: {"subject": "...", "expression": "...", "answer": "...", "steps": [...], "explanation": "..."}.\n'
      'Do not include markdown ticks or any text outside the JSON object.';

  @visibleForTesting
  static HandwritingMathResult? parseAiResponse(
    String content,
    List<Stroke> strokes,
  ) {
    try {
      String expression = '';
      String answer = '';
      List<String> steps = [];
      String? explanation;

      // 1. Try finding JSON object in response
      String jsonStr = content.trim();
      final startIdx = jsonStr.indexOf('{');
      final endIdx = jsonStr.lastIndexOf('}');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        try {
          final data =
              jsonDecode(jsonStr.substring(startIdx, endIdx + 1))
                  as Map<String, dynamic>;
          expression = (data['expression'] as String?)?.trim() ?? '';
          answer = data['answer']?.toString().trim() ?? '';
          if (data['steps'] is List) {
            steps = (data['steps'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          final expl = (data['explanation'] as String?)?.trim();
          if (expl != null && expl.isNotEmpty) {
            explanation = expl;
          }
        } catch (_) {}
      }

      // If the AI explicitly reported no math expression:
      if (expression.isEmpty && answer.isEmpty) {
        return null;
      }

      // Guard against raw JSON string leaks in answer or expression
      if (answer.contains('expression') ||
          answer.contains('answer') ||
          answer.contains('{') ||
          answer.contains('}') ||
          expression.contains('expression') ||
          expression.contains('answer') ||
          expression.contains('{') ||
          expression.contains('}')) {
        return null;
      }

      // 2. If JSON didn't yield an answer, parse direct plaintext response (common in reasoning models)
      if (answer.isEmpty) {
        var clean = content
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        // If clean contains json markers, reject
        if (clean.contains('{') || clean.contains('}')) {
          return null;
        }
        // Remove trailing or leading quotes
        if (clean.startsWith('"') && clean.endsWith('"') && clean.length > 2) {
          clean = clean.substring(1, clean.length - 1).trim();
        }
        if (clean.contains('=')) {
          final eqIdx = clean.indexOf('=');
          expression = clean.substring(0, eqIdx).trim();
          answer = clean.substring(eqIdx + 1).trim();
        } else {
          answer = clean;
          expression = '';
        }
      }

      if (answer.isEmpty) return null;
      if (expression.isEmpty) expression = answer;

      // Double-check no JSON artifacts in answer or expression
      if (answer.contains('{') ||
          answer.contains('}') ||
          answer.contains('expression') ||
          answer.contains('answer') ||
          expression.contains('{') ||
          expression.contains('}') ||
          expression.contains('expression') ||
          expression.contains('answer')) {
        return null;
      }

      // Calculate placement: placed directly after '=' along teacher's baseline slant
      Rect? unionBounds;
      for (final s in strokes) {
        unionBounds = unionBounds == null
            ? s.bounds
            : unionBounds.expandToInclude(s.bounds);
      }
      unionBounds ??= Rect.zero;

      final lastStroke = strokes.last;
      final eq = HandwritingMathEngine.detectAngleInvariantEqualSign(strokes);

      Offset insertPos;
      Offset dir = const Offset(1, 0);
      Offset normal = const Offset(0, 1);
      double avgHeight;

      if (eq != null) {
        dir = eq.direction;
        normal = eq.normal;
        avgHeight = math.max(28.0, math.min(140.0, eq.length * 1.5));
        insertPos =
            eq.center +
            dir * (eq.length * 0.9 + 25.0) -
            normal * (avgHeight * 0.5);
      } else {
        avgHeight = math.max(28.0, math.min(120.0, unionBounds.height * 0.70));
        insertPos = Offset(
          unionBounds.right + 25.0,
          unionBounds.center.dy - (avgHeight * 0.5),
        );
      }

      return HandwritingMathResult(
        // Keep "→" (chemistry) and "?" endings; only add "=" otherwise.
        expression: RegExp(r'[=→?]\s*$').hasMatch(expression)
            ? expression
            : '$expression =',
        answer: answer,
        insertPosition: insertPos,
        characterHeight: avgHeight,
        strokeColorValue: lastStroke.colorValue,
        strokeWidth: lastStroke.width,
        direction: dir,
        normal: normal,
        steps: steps,
        explanation: explanation,
      );
    } catch (_) {
      return null;
    }
  }

  /// Renders a list of vector strokes into a crisp, high-contrast black-and-white PNG
  /// with uniform scaling to ensure complete diagram is preserved without cropping.
  static Future<String?> renderStrokesToBase64Png(
    List<Stroke> strokes, {
    double padding = 24.0,
  }) async {
    if (strokes.isEmpty) return null;

    Rect? bounds;
    for (final s in strokes) {
      bounds = bounds == null ? s.bounds : bounds.expandToInclude(s.bounds);
    }
    if (bounds == null || bounds.width < 5 || bounds.height < 5) return null;

    final padded = bounds.inflate(padding);

    // Compute scale so complete canvas/diagram fits inside 1024x1024 without cropping
    double scale = 1.0;
    final maxDim = math.max(padded.width, padded.height);
    if (maxDim > 1024.0) {
      scale = 1024.0 / maxDim;
    }
    final width = (padded.width * scale).toInt().clamp(64, 1024);
    final height = (padded.height * scale).toInt().clamp(64, 1024);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Fill white background for clear contrast
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bgPaint,
    );

    canvas.save();
    canvas.scale(scale, scale);
    canvas.translate(-padded.left, -padded.top);

    for (final s in strokes) {
      final inkPaint = Paint()
        ..color = const Color(0xFF000000)
        ..strokeWidth = math.max(3.5, s.width * 1.25)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(s.path, inkPaint);
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    return base64Encode(byteData.buffer.asUint8List());
  }
}
