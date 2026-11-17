import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;

import '../models/stroke_model.dart';

/// On-device handwriting reader (Google ML Kit Digital Ink).
///
/// Reads a line of handwriting in a few tens of milliseconds, offline, so
/// plain arithmetic is answered without a round trip to the AI. The model
/// (about 20 MB) is downloaded once; until it's ready, [recognize] returns
/// null and callers fall back to the built-in rules.
class InkRecognizer {
  InkRecognizer._();

  static const String language = 'en';

  /// Replaces recognition in tests.
  @visibleForTesting
  static Future<List<String>?> Function(List<Stroke> strokes)? debugOverride;

  static mlkit.DigitalInkRecognizer? _recognizer;
  static bool _ready = false;
  static Future<bool>? _preparing;

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Makes sure the model is on the device. Safe to call repeatedly.
  static Future<bool> prepare() {
    if (_ready) return Future.value(true);
    if (!supported) return Future.value(false);
    return _preparing ??= _prepare().whenComplete(() => _preparing = null);
  }

  static Future<bool> _prepare() async {
    try {
      final models = mlkit.DigitalInkRecognizerModelManager();
      if (!await models.isModelDownloaded(language)) {
        if (!await models.downloadModel(language, isWifiRequired: false)) {
          return false;
        }
      }
      _recognizer ??= mlkit.DigitalInkRecognizer(languageCode: language);
      _ready = true;
      return true;
    } catch (e) {
      debugPrint('InkRecognizer: model unavailable: $e');
      return false;
    }
  }

  /// Candidate readings of [strokes], best first. Null when the reader isn't
  /// available (unsupported platform, model not downloaded yet, error).
  static Future<List<String>?> recognize(List<Stroke> strokes) async {
    final override = debugOverride;
    if (override != null) return override(strokes);
    if (strokes.isEmpty) return const [];
    if (!_ready) {
      unawaited(prepare());
      return null;
    }
    try {
      final ink = mlkit.Ink()
        ..strokes = [
          for (final s in strokes)
            if (s.points.isNotEmpty)
              mlkit.Stroke()
                ..points = [
                  for (final p in s.points)
                    mlkit.StrokePoint(x: p.x, y: p.y, t: p.timestamp),
                ],
        ];
      var bounds = strokes.first.bounds;
      for (final s in strokes) {
        bounds = bounds.expandToInclude(s.bounds);
      }
      final candidates = await _recognizer!
          .recognize(
            ink,
            context: mlkit.DigitalInkRecognitionContext(
              preContext: '',
              writingArea: mlkit.WritingArea(
                width: bounds.width + 40,
                height: bounds.height * 1.4 + 20,
              ),
            ),
          )
          .timeout(const Duration(seconds: 2));
      return [for (final c in candidates) c.text];
    } catch (e) {
      debugPrint('InkRecognizer: recognition failed: $e');
      return null;
    }
  }
}
