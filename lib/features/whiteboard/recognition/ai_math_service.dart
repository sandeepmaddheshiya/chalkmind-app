import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/stroke_model.dart';
import 'handwriting_math_engine.dart';

class AiMathService {
  static const String _defaultApiKey =
      'REMOVED-LEAKED-KEY';
  static const String _defaultModel = 'google/gemini-2.5-flash';
  static const String _fallbackModel = 'google/gemini-2.5-flash-lite';

  /// Solves mathematical expressions, equations, and geometry diagrams directly from strokes
  /// using multimodal vision intelligence via OpenRouter.
  static Future<HandwritingMathResult?> solveWithVisionAI({
    required List<Stroke> strokes,
    String? customApiKey,
    String? customModel,
  }) async {
    if (strokes.isEmpty) return null;

    final base64Image = await renderStrokesToBase64Png(strokes);
    if (base64Image == null) return null;

    final apiKey = (customApiKey != null && customApiKey.isNotEmpty)
        ? customApiKey
        : _defaultApiKey;

    final promptText =
        'You are an expert mathematics and geometry assistant for a digital teacher whiteboard.\n'
        'Analyze this handwriting image containing mathematical expressions, formulas, algebra, geometry diagrams, or equations.\n'
        '1. If it contains an algebraic formula, identity, or expression to factor or expand (e.g. "a³ - b³ =", "(a + b)² =", "a² - b² =", "x² - 9 ="):\n'
        'Provide the factored or expanded algebraic identity.\n'
        'Example:\n'
        '{"expression": "a³ - b³ =", "answer": "(a - b)(a² + ab + b²)", "steps": ["Identify difference of cubes identity: u³ - v³ = (u - v)(u² + uv + v²)", "Set u = a and v = b", "Factor: (a - b)(a² + ab + b²)"], "explanation": "Difference of cubes factors into a linear binomial and an irreducible quadratic."}\n'
        '2. If it contains a geometry figure or diagram (e.g. a right triangle with legs 3 and 4, hypotenuse x, with "x =" or "x"):\n'
        'Apply geometric theorems (such as Pythagorean theorem a² + b² = c², trigonometry, angle sum, area, perimeter) to solve for the requested unknown variable.\n'
        'Example response for a right triangle with legs 3, 4 and hypotenuse x:\n'
        '{"expression": "x = √(3² + 4²) =", "answer": "5", "steps": ["State Pythagorean theorem: a² + b² = c²", "Substitute legs: 3² + 4² = x² => 9 + 16 = 25", "Take square root: x = √25 = 5"], "explanation": "In any right triangle, the square of the hypotenuse equals the sum of squares of the legs."}\n'
        '3. If it contains a system of equations or variables (e.g. "x = 3", "y = x + 2", "y ="):\n'
        'Solve for the requested variable by substituting known values into the equation.\n'
        'Example: if x = 3 and y = x + 2, solving for y gives:\n'
        '{"expression": "y = 3 + 2 =", "answer": "5", "steps": ["Substitute x = 3 into y = x + 2", "Compute y = 3 + 2 = 5"], "explanation": "Solved by direct algebraic substitution."}\n'
        '4. If it contains arithmetic or algebra (e.g. "9 * 12 =", "2² + 5 =", "15 + 25 ="):\n'
        'Carefully transcribe every digit and operator accurately without making silly mistakes. Calculate the exact solution.\n'
        'Respond ONLY with a valid JSON object in this format:\n'
        '{"expression": "...", "answer": "...", "steps": ["Step 1...", "Step 2..."], "explanation": "..."}\n'
        'Keep the "answer" field concise (e.g. "(a - b)(a² + ab + b²)" or "5" or "108").\n'
        'If the image is not a math expression or question, respond strictly with {"expression": "", "answer": ""}.\n'
        'Do not include markdown ticks or any text outside the JSON object.';

    final candidates = [
      if (customModel != null && customModel.isNotEmpty) customModel,
      _defaultModel,
      _fallbackModel,
      'google/gemini-3.5-flash-lite',
      'dots-studio/dots-3-note-preview:free',
    ];

    for (final candidateModel in candidates) {
      try {
        debugPrint('AiMathService: sending request to $candidateModel');
        final response = await http.post(
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://boardflow.app',
            'X-Title': 'BoardFlow Whiteboard',
          },
          body: jsonEncode({
            'model': candidateModel,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'text',
                    'text': promptText,
                  },
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:image/png;base64,$base64Image',
                    },
                  },
                ],
              },
            ],
            'temperature': 0.1,
          }),
        ).timeout(const Duration(seconds: 12));

        debugPrint('AiMathService: response status=${response.statusCode}');
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final choices = decoded['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final message = choices[0]['message'] as Map<String, dynamic>?;
            final content = message?['content'] as String?;
            debugPrint('AiMathService: raw content=$content');
            if (content != null && content.isNotEmpty) {
              final parsed = _parseAiResponse(content, strokes);
              if (parsed != null) {
                debugPrint('AiMathService: parsed result=${parsed.expression} ${parsed.answer}');
                return parsed;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('AiMathService error on $candidateModel: $e');
      }
    }

    return null;
  }

  static HandwritingMathResult? _parseAiResponse(String content, List<Stroke> strokes) {
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
          final data = jsonDecode(jsonStr.substring(startIdx, endIdx + 1)) as Map<String, dynamic>;
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
        unionBounds = unionBounds == null ? s.bounds : unionBounds.expandToInclude(s.bounds);
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
        insertPos = eq.center + dir * (eq.length * 0.9 + 25.0) - normal * (avgHeight * 0.5);
      } else {
        avgHeight = math.max(28.0, math.min(120.0, unionBounds.height * 0.70));
        insertPos = Offset(unionBounds.right + 25.0, unionBounds.center.dy - (avgHeight * 0.5));
      }

      return HandwritingMathResult(
        expression: expression.endsWith('=') ? expression : '$expression =',
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
  static Future<String?> renderStrokesToBase64Png(List<Stroke> strokes, {double padding = 24.0}) async {
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
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    // Fill white background for clear contrast
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), bgPaint);

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
