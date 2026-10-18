import 'dart:math' as math;
import 'universal_math_engine.dart';

class MathEvaluationResult {
  final String expression;
  final String resultText;
  final double numericResult;
  final String fullEquation; // e.g., "15 * 8 = 120"

  const MathEvaluationResult({
    required this.expression,
    required this.resultText,
    required this.numericResult,
    required this.fullEquation,
  });
}

class MathEvaluator {
  /// Check if a string contains a solvable math expression (e.g. ending in '=' or standard formula)
  static MathEvaluationResult? evaluate(String rawInput) {
    if (rawInput.trim().isEmpty) return null;

    // 1. Check if this is an algebraic identity, formula, calculus, or trigonometric expansion (0ms instant!)
    final identityResult = UniversalMathEngine.solveAlgebraicIdentity(rawInput);
    if (identityResult != null) {
      final originalClean = rawInput.trim();
      final fullEquation = originalClean.endsWith('=')
          ? '$originalClean $identityResult'
          : '$originalClean = $identityResult';
      return MathEvaluationResult(
        expression: originalClean,
        resultText: identityResult,
        numericResult: double.nan,
        fullEquation: fullEquation,
      );
    }

    String text = rawInput.trim();

    // Clean up equation formatting
    if (text.endsWith('=')) {
      text = text.substring(0, text.length - 1).trim();
    } else if (text.endsWith('?')) {
      text = text.substring(0, text.length - 1).trim();
    }

    if (text.isEmpty) return null;

    // Normalize teacher symbols
    text = text
        .replaceAll('×', '*')
        .replaceAll('·', '*')
        .replaceAll('÷', '/')
        .replaceAll('²', '^2')
        .replaceAll('³', '^3')
        .replaceAll('√', 'sqrt');

    // Handle "X% of Y" format (e.g. "15% of 800" -> "(15/100)*800")
    final percentOfRegex = RegExp(r'(\d+(?:\.\d+)?)\s*%\s*of\s*(\d+(?:\.\d+)?)', caseSensitive: false);
    text = text.replaceAllMapped(percentOfRegex, (m) {
      final p = m.group(1)!;
      final val = m.group(2)!;
      return '(($p / 100) * $val)';
    });

    // Handle general percentage (e.g. "50%" -> "(50/100)")
    text = text.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s*%'), (m) {
      final p = m.group(1)!;
      return '($p / 100)';
    });

    // A solvable arithmetic calculation must contain at least one operation (+, -, *, /, ^, or math function)
    final hasOp = RegExp(r'[+\-*/^]|sqrt|sin|cos|tan|log|ln|abs').hasMatch(text);
    if (!hasOp) return null;

    try {
      final parser = _Parser(text);
      final value = parser.parse();

      if (value.isNaN || value.isInfinite) return null;

      String formattedResult;
      if (value == value.roundToDouble() && !value.abs().toString().contains('e')) {
        formattedResult = value.toInt().toString();
      } else {
        formattedResult = value.toStringAsFixed(4);
        // Trim trailing zeros
        while (formattedResult.endsWith('0')) {
          formattedResult = formattedResult.substring(0, formattedResult.length - 1);
        }
        if (formattedResult.endsWith('.')) {
          formattedResult = formattedResult.substring(0, formattedResult.length - 1);
        }
      }

      final originalClean = rawInput.trim();
      final fullEquation = originalClean.endsWith('=')
          ? '$originalClean $formattedResult'
          : '$originalClean = $formattedResult';

      return MathEvaluationResult(
        expression: rawInput.trim(),
        resultText: formattedResult,
        numericResult: value,
        fullEquation: fullEquation,
      );
    } catch (_) {
      return null;
    }
  }
}

class _Parser {
  final String input;
  int _pos = -1;
  int _ch = -1;

  _Parser(this.input);

  void _nextChar() {
    _pos++;
    _ch = (_pos < input.length) ? input.codeUnitAt(_pos) : -1;
  }

  bool _eat(int charToEat) {
    while (_ch == 32) {
      _nextChar(); // skip spaces
    }
    if (_ch == charToEat) {
      _nextChar();
      return true;
    }
    return false;
  }

  double parse() {
    _nextChar();
    final x = _parseExpression();
    if (_pos < input.length) {
      throw FormatException('Unexpected: ${String.fromCharCode(_ch)}');
    }
    return x;
  }

  // Grammar:
  // expression = term | expression `+` term | expression `-` term
  // term = factor | term `*` factor | term `/` factor
  // factor = `+` factor | `-` factor | `(` expression `)` | number | functionName factor | factor `^` factor

  double _parseExpression() {
    double x = _parseTerm();
    for (;;) {
      if (_eat(43)) {
        x += _parseTerm(); // +
      } else if (_eat(45)) {
        x -= _parseTerm(); // -
      } else {
        return x;
      }
    }
  }

  double _parseTerm() {
    double x = _parseFactor();
    for (;;) {
      if (_eat(42)) {
        x *= _parseFactor(); // *
      } else if (_eat(47)) {
        final divisor = _parseFactor(); // /
        if (divisor == 0) throw const FormatException('Division by zero');
        x /= divisor;
      } else {
        return x;
      }
    }
  }

  double _parseFactor() {
    if (_eat(43)) return _parseFactor(); // unary plus
    if (_eat(45)) return -_parseFactor(); // unary minus

    double x;
    final startPos = _pos;

    if (_eat(40)) {
      // (
      x = _parseExpression();
      if (!_eat(41)) throw const FormatException('Missing closing parenthesis');
    } else if ((_ch >= 48 && _ch <= 57) || _ch == 46) {
      // numbers 0-9 or .
      while ((_ch >= 48 && _ch <= 57) || _ch == 46) {
        _nextChar();
      }
      x = double.parse(input.substring(startPos, _pos));
    } else if (_ch >= 97 && _ch <= 122) {
      // letters (functions)
      while (_ch >= 97 && _ch <= 122) {
        _nextChar();
      }
      final func = input.substring(startPos, _pos);
      x = _parseFactor();

      if (func == 'sqrt') {
        if (x < 0) throw const FormatException('Square root of negative number');
        x = math.sqrt(x);
      } else if (func == 'sin') {
        // Teacher math: degrees by default
        x = math.sin(x * math.pi / 180.0);
      } else if (func == 'cos') {
        x = math.cos(x * math.pi / 180.0);
      } else if (func == 'tan') {
        x = math.tan(x * math.pi / 180.0);
      } else if (func == 'log') {
        x = math.log(x) / math.ln10; // Log base 10
      } else if (func == 'ln') {
        x = math.log(x); // Natural log
      } else if (func == 'abs') {
        x = x.abs();
      } else {
        throw FormatException('Unknown function: $func');
      }
    } else {
      throw FormatException('Unexpected token at position $_pos');
    }

    // Exponentiation ^
    if (_eat(94)) {
      x = math.pow(x, _parseFactor()).toDouble();
    }

    return x;
  }
}
