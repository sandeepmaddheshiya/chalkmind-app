import 'dart:math' as math;

/// Represents a mathematically significant point on a function curve
/// (Root / X-Intercept, Y-Intercept, Local Extrema / Vertex, or Singularity).
class KeyPoint {
  final double x;
  final double y;
  final String label;
  final String pointType; // 'root', 'y-intercept', 'vertex', 'extrema'

  const KeyPoint({
    required this.x,
    required this.y,
    required this.label,
    required this.pointType,
  });

  String get coordinateText => '(${_formatNum(x)}, ${_formatNum(y)})';

  static String _formatNum(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-4) {
      return v.round().toString();
    }
    return v.toStringAsFixed(2);
  }
}

/// Evaluates mathematical functions $y = f(x)$ for live Desmos-style plotting.
class MathFunction {
  final String rawInput;
  final String cleanFormula; // e.g. "y = x² - 4"
  final double Function(double x) evaluate;
  final double Function(double x)?
  evaluateNegativeBranch; // for circles: x² + y² = r²
  final bool isImplicitCircle;
  final double circleRadius;

  const MathFunction({
    required this.rawInput,
    required this.cleanFormula,
    required this.evaluate,
    this.evaluateNegativeBranch,
    this.isImplicitCircle = false,
    this.circleRadius = 0.0,
  });

  /// Calculates key points (roots, y-intercept, vertex/extrema) within the visible range.
  List<KeyPoint> findKeyPoints(double xMin, double xMax) {
    final keyPoints = <KeyPoint>[];

    // Special case: Implicit circle x² + y² = r²
    if (isImplicitCircle && circleRadius > 0) {
      final r = circleRadius;
      keyPoints.add(
        KeyPoint(x: r, y: 0, label: 'Intercept (r, 0)', pointType: 'root'),
      );
      keyPoints.add(
        KeyPoint(x: -r, y: 0, label: 'Intercept (-r, 0)', pointType: 'root'),
      );
      keyPoints.add(
        KeyPoint(
          x: 0,
          y: r,
          label: 'Intercept (0, r)',
          pointType: 'y_intercept',
        ),
      );
      keyPoints.add(
        KeyPoint(
          x: 0,
          y: -r,
          label: 'Intercept (0, -r)',
          pointType: 'y_intercept',
        ),
      );
      return keyPoints;
    }

    // 1. Y-Intercept: f(0)
    if (xMin <= 0 && xMax >= 0) {
      try {
        final y0 = evaluate(0.0);
        if (!y0.isNaN && !y0.isInfinite) {
          keyPoints.add(
            KeyPoint(
              x: 0.0,
              y: y0,
              label: 'Y-Intercept',
              pointType: 'y_intercept',
            ),
          );
        }
      } catch (_) {}
    }

    // 2. Numerical root and extrema finder
    const steps = 300;
    final dx = (xMax - xMin) / steps;
    if (dx <= 0) return keyPoints;

    double? prevX;
    double? prevY;
    double? prevDy;

    for (int i = 0; i <= steps; i++) {
      final x = xMin + i * dx;
      double y;
      try {
        y = evaluate(x);
      } catch (_) {
        continue;
      }
      if (y.isNaN || y.isInfinite) {
        prevX = null;
        prevY = null;
        prevDy = null;
        continue;
      }

      // Root detection via sign change
      if (prevY != null && prevX != null) {
        if ((prevY * y < 0) || y.abs() < 1e-6) {
          // Refine root using bisection
          final rootX = _refineRoot(prevX, x, evaluate);
          if (rootX != null) {
            // Avoid duplicate roots within 0.1
            final isDuplicate = keyPoints.any(
              (p) => p.pointType == 'root' && (p.x - rootX).abs() < 0.15,
            );
            if (!isDuplicate) {
              keyPoints.add(
                KeyPoint(
                  x: rootX,
                  y: 0.0,
                  label: 'Root (Zero)',
                  pointType: 'root',
                ),
              );
            }
          }
        }
      }

      // Local Extrema (Vertex / Min / Max) via derivative sign change
      if (prevX != null && prevY != null) {
        final currentDy = (y - prevY) / dx;
        if (prevDy != null) {
          if (prevDy * currentDy < 0 && (currentDy - prevDy).abs() > 1e-4) {
            final extremaX = (prevX + x) / 2;
            final extremaY = evaluate(extremaX);
            if (!extremaY.isNaN && !extremaY.isInfinite) {
              final isDuplicate = keyPoints.any(
                (p) =>
                    (p.pointType == 'vertex' || p.pointType == 'extrema') &&
                    (p.x - extremaX).abs() < 0.25,
              );
              if (!isDuplicate) {
                final isMin = currentDy > prevDy;
                keyPoints.add(
                  KeyPoint(
                    x: extremaX,
                    y: extremaY,
                    label: isMin ? 'Minimum / Vertex' : 'Maximum / Peak',
                    pointType: 'vertex',
                  ),
                );
              }
            }
          }
        }
        prevDy = currentDy;
      }

      prevX = x;
      prevY = y;
    }

    return keyPoints;
  }

  static double? _refineRoot(double a, double b, double Function(double x) fn) {
    double fa = fn(a);
    double fb = fn(b);
    if (fa.isNaN || fb.isNaN) return null;
    if (fa.abs() < 1e-5) return a;
    if (fb.abs() < 1e-5) return b;
    if (fa * fb > 0) return null;

    double left = a;
    double right = b;
    for (int iter = 0; iter < 16; iter++) {
      final mid = (left + right) / 2;
      final fmid = fn(mid);
      if (fmid.isNaN) return null;
      if (fmid.abs() < 1e-5) return mid;
      if (fa * fmid < 0) {
        right = mid;
        fb = fmid;
      } else {
        left = mid;
        fa = fmid;
      }
    }
    return (left + right) / 2;
  }
}

/// Parses handwritten or typed equation strings into graphable [MathFunction] instances.
class MathFunctionParser {
  /// Checks whether an input string looks like a plot-ready function equation
  /// (e.g. "y = x^2 - 4", "f(x) = sin(x)", "y = 2x + 1", "x^2 + y^2 = 25", "y = sqrt(x)").
  static bool isGraphable(String text) {
    return parse(text) != null;
  }

  /// Parses text into a [MathFunction]. Returns null if not a valid single-variable function.
  static MathFunction? parse(String text) {
    String s = text.trim().toLowerCase();
    if (s.isEmpty) return null;

    // Remove markdown math delimiters if present
    s = s.replaceAll(r'\$', '').replaceAll(r'$$', '').trim();

    // 1. Implicit Circle check: x^2 + y^2 = r^2
    final circleMatch = RegExp(
      r'x\s*(\^2|²)\s*\+\s*y\s*(\^2|²)\s*=\s*([0-9\.]+)',
    ).firstMatch(s);
    if (circleMatch != null) {
      final rSquared = double.tryParse(circleMatch.group(3)!) ?? 25.0;
      final r = math.sqrt(rSquared);
      return MathFunction(
        rawInput: text,
        cleanFormula:
            'x² + y² = ${rSquared.toStringAsFixed(rSquared.truncateToDouble() == rSquared ? 0 : 2)}',
        isImplicitCircle: true,
        circleRadius: r,
        evaluate: (x) {
          final diff = rSquared - x * x;
          return diff >= 0 ? math.sqrt(diff) : double.nan;
        },
        evaluateNegativeBranch: (x) {
          final diff = rSquared - x * x;
          return diff >= 0 ? -math.sqrt(diff) : double.nan;
        },
      );
    }

    // 2. Extract RHS if starts with "y =" or "f(x) ="
    String expr = s;
    if (s.startsWith('y=') || s.startsWith('y =')) {
      expr = s.substring(s.indexOf('=') + 1).trim();
    } else if (s.startsWith('f(x)=') || s.startsWith('f(x) =')) {
      expr = s.substring(s.indexOf('=') + 1).trim();
    } else if (s.endsWith('=y') || s.endsWith('= y')) {
      expr = s.substring(0, s.lastIndexOf('=')).trim();
    } else if (s.contains('=') && !s.contains('==')) {
      // e.g. "x^2 - 4 = 0" -> plot y = x^2 - 4
      final parts = s.split('=');
      if (parts[1].trim() == '0' || parts[1].trim().isEmpty) {
        expr = parts[0].trim();
      } else {
        return null;
      }
    }

    if (expr.isEmpty) return null;

    // Must contain 'x' to be a function of x
    if (!expr.contains('x')) {
      // Constant function y = c
      final c = double.tryParse(expr);
      if (c != null) {
        return MathFunction(
          rawInput: text,
          cleanFormula: 'y = $c',
          evaluate: (x) => c,
        );
      }
      return null;
    }

    // Tokenize and build evaluator
    try {
      final evaluator = _compileExpression(expr);
      // Validate by sampling a few values
      final test1 = evaluator(0.0);
      final test2 = evaluator(1.0);
      final test3 = evaluator(-1.0);
      if (test1.isNaN && test2.isNaN && test3.isNaN) {
        return null;
      }

      // Format clean display formula
      String clean = expr
          .replaceAll('^2', '²')
          .replaceAll('^3', '³')
          .replaceAll('*', ' · ');
      if (!clean.startsWith('y =')) {
        clean = 'y = $clean';
      }

      return MathFunction(
        rawInput: text,
        cleanFormula: clean,
        evaluate: evaluator,
      );
    } catch (_) {
      return null;
    }
  }

  /// Compiles a math expression string into a function f(x): R -> R.
  static double Function(double x) _compileExpression(String expr) {
    // Normalize string tokens
    String e = expr
        .replaceAll(' ', '')
        .replaceAll('²', '^2')
        .replaceAll('³', '^3')
        .replaceAll('·', '*')
        .replaceAll('−', '-')
        .replaceAll('×', '*');

    // Replace implicit multiplication like "2x" -> "2*x", "3sin(x)" -> "3*sin(x)"
    e = e.replaceAllMapped(
      RegExp(r'(\d)([a-zA-Z\(])'),
      (m) => '${m.group(1)}*${m.group(2)}',
    );
    e = e.replaceAllMapped(
      RegExp(r'(\))([a-zA-Z\d\(])'),
      (m) => '${m.group(1)}*${m.group(2)}',
    );
    e = e.replaceAllMapped(
      RegExp(r'([xX])([a-zA-Z\(])'),
      (m) => '${m.group(1)}*${m.group(2)}',
    );

    return (double xVal) {
      return _evaluateTokens(e, xVal);
    };
  }

  static double _evaluateTokens(String expr, double x) {
    // Handle binary + and - at top level (outside parentheses)
    int parenDepth = 0;
    for (int i = expr.length - 1; i >= 0; i--) {
      final c = expr[i];
      if (c == ')') {
        parenDepth++;
      } else if (c == '(') {
        parenDepth--;
      } else if (parenDepth == 0) {
        if (c == '+' &&
            i > 0 &&
            expr[i - 1] != '*' &&
            expr[i - 1] != '/' &&
            expr[i - 1] != '^') {
          return _evaluateTokens(expr.substring(0, i), x) +
              _evaluateTokens(expr.substring(i + 1), x);
        } else if (c == '-' &&
            i > 0 &&
            expr[i - 1] != '*' &&
            expr[i - 1] != '/' &&
            expr[i - 1] != '^') {
          return _evaluateTokens(expr.substring(0, i), x) -
              _evaluateTokens(expr.substring(i + 1), x);
        }
      }
    }

    // Handle * and /
    parenDepth = 0;
    for (int i = expr.length - 1; i >= 0; i--) {
      final c = expr[i];
      if (c == ')') {
        parenDepth++;
      } else if (c == '(') {
        parenDepth--;
      } else if (parenDepth == 0) {
        if (c == '*') {
          return _evaluateTokens(expr.substring(0, i), x) *
              _evaluateTokens(expr.substring(i + 1), x);
        } else if (c == '/') {
          final denom = _evaluateTokens(expr.substring(i + 1), x);
          if (denom.abs() < 1e-9) return double.nan;
          return _evaluateTokens(expr.substring(0, i), x) / denom;
        }
      }
    }

    // Handle ^ (power)
    parenDepth = 0;
    for (int i = 0; i < expr.length; i++) {
      final c = expr[i];
      if (c == '(') {
        parenDepth++;
      } else if (c == ')') {
        parenDepth--;
      } else if (parenDepth == 0 && c == '^') {
        final base = _evaluateTokens(expr.substring(0, i), x);
        final exponent = _evaluateTokens(expr.substring(i + 1), x);
        if (base < 0 && (exponent - exponent.round()).abs() < 1e-6) {
          final expInt = exponent.round();
          final res = math.pow(base.abs(), exponent).toDouble();
          return expInt % 2 == 1 ? -res : res;
        }
        return math.pow(base, exponent).toDouble();
      }
    }

    // Leading negative sign: e.g. -x^2
    if (expr.startsWith('-')) {
      return -_evaluateTokens(expr.substring(1), x);
    }

    // Parentheses: (inner)
    if (expr.startsWith('(') && expr.endsWith(')')) {
      return _evaluateTokens(expr.substring(1, expr.length - 1), x);
    }

    // Functions: sin, cos, tan, sqrt, abs, ln, log, exp
    if (expr.startsWith('sin(') && expr.endsWith(')')) {
      return math.sin(_evaluateTokens(expr.substring(4, expr.length - 1), x));
    }
    if (expr.startsWith('cos(') && expr.endsWith(')')) {
      return math.cos(_evaluateTokens(expr.substring(4, expr.length - 1), x));
    }
    if (expr.startsWith('tan(') && expr.endsWith(')')) {
      return math.tan(_evaluateTokens(expr.substring(4, expr.length - 1), x));
    }
    if (expr.startsWith('sqrt(') && expr.endsWith(')')) {
      final val = _evaluateTokens(expr.substring(5, expr.length - 1), x);
      return val >= 0 ? math.sqrt(val) : double.nan;
    }
    if (expr.startsWith('abs(') && expr.endsWith(')')) {
      return _evaluateTokens(expr.substring(4, expr.length - 1), x).abs();
    }
    if (expr.startsWith('ln(') && expr.endsWith(')')) {
      final val = _evaluateTokens(expr.substring(3, expr.length - 1), x);
      return val > 0 ? math.log(val) : double.nan;
    }
    if (expr.startsWith('log(') && expr.endsWith(')')) {
      final val = _evaluateTokens(expr.substring(4, expr.length - 1), x);
      return val > 0 ? (math.log(val) / math.ln10) : double.nan;
    }
    if (expr.startsWith('exp(') && expr.endsWith(')')) {
      return math.exp(_evaluateTokens(expr.substring(4, expr.length - 1), x));
    }

    // Variable x
    if (expr == 'x' || expr == 'X') {
      return x;
    }

    // Mathematical constants
    if (expr == 'pi' || expr == 'π') {
      return math.pi;
    }
    if (expr == 'e') {
      return math.e;
    }

    // Constant number
    final num = double.tryParse(expr);
    if (num != null) {
      return num;
    }

    return double.nan;
  }
}
