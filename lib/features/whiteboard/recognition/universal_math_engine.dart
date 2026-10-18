import 'dart:math' as math;

class StepByStepSolution {
  final String title;
  final String input;
  final List<String> steps;
  final String result;
  final Map<String, dynamic> data;

  const StepByStepSolution({
    required this.title,
    required this.input,
    required this.steps,
    required this.result,
    this.data = const {},
  });

  /// Formatted multi-line text ready to be inserted directly onto the whiteboard canvas
  String get formattedBoardText {
    final buffer = StringBuffer();
    buffer.writeln('── $title ──');
    buffer.writeln('Given: $input');
    buffer.writeln('');
    for (int i = 0; i < steps.length; i++) {
      buffer.writeln('Step ${i + 1}: ${steps[i]}');
    }
    buffer.writeln('');
    buffer.writeln('Result: $result');
    return buffer.toString().trim();
  }
}

class UniversalMathEngine {
  // Helper to format clean decimals
  static String formatNum(double val) {
    if (val.isNaN) return 'NaN';
    if (val.isInfinite) return val > 0 ? '∞' : '-∞';
    if (val == val.roundToDouble() && val.abs() < 1e12) {
      return val.toInt().toString();
    }
    final fixed = val.toStringAsFixed(4);
    var clean = fixed;
    while (clean.endsWith('0')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  // =========================================================================
  // ALGEBRA SOLVERS
  // =========================================================================

  /// Solves quadratic equation ax² + bx + c = 0 with full step-by-step derivation
  static StepByStepSolution solveQuadratic({
    required double a,
    required double b,
    required double c,
  }) {
    if (a == 0) {
      return solveLinearEquation(a: b, b: c, c: 0);
    }

    final steps = <String>[];
    final disc = b * b - 4 * a * c;
    final aStr = formatNum(a);
    final bStr = formatNum(b);
    final cStr = formatNum(c);

    steps.add('Equation: ${aStr}x² ${b >= 0 ? '+' : '-'} ${formatNum(b.abs())}x ${c >= 0 ? '+' : '-'} ${formatNum(c.abs())} = 0');
    steps.add('Identify coefficients: a = $aStr, b = $bStr, c = $cStr');
    steps.add('Calculate Discriminant: Δ = b² - 4ac = ($bStr)² - 4($aStr)($cStr) = ${formatNum(disc)}');

    String resultText;
    final h = -b / (2 * a);
    final k = c - (b * b) / (4 * a);

    if (disc > 0) {
      final sqrtD = math.sqrt(disc);
      final r1 = (-b + sqrtD) / (2 * a);
      final r2 = (-b - sqrtD) / (2 * a);
      steps.add('Since Δ > 0, there are two distinct real roots.');
      steps.add('Apply formula: x = (-b ± √Δ) / 2a = (-($bStr) ± ${formatNum(sqrtD)}) / (2 · $aStr)');
      steps.add('x₁ = (-($bStr) + ${formatNum(sqrtD)}) / ${formatNum(2 * a)} = ${formatNum(r1)}');
      steps.add('x₂ = (-($bStr) - ${formatNum(sqrtD)}) / ${formatNum(2 * a)} = ${formatNum(r2)}');
      steps.add('Parabola Vertex: (h, k) = (${formatNum(h)}, ${formatNum(k)})');
      resultText = 'x = ${formatNum(r1)}  or  x = ${formatNum(r2)}';
    } else if (disc == 0) {
      final r = -b / (2 * a);
      steps.add('Since Δ = 0, there is exactly one repeated real root.');
      steps.add('x = -b / 2a = -($bStr) / (2 · $aStr) = ${formatNum(r)}');
      steps.add('Parabola Vertex: (h, k) = (${formatNum(h)}, 0)');
      resultText = 'x = ${formatNum(r)} (double root)';
    } else {
      final realPart = -b / (2 * a);
      final imagPart = math.sqrt(-disc) / (2 * a.abs());
      steps.add('Since Δ < 0, there are two complex conjugate roots.');
      steps.add('√Δ = i√(${formatNum(-disc)}) = ${formatNum(math.sqrt(-disc))}i');
      steps.add('x = ${formatNum(realPart)} ± ${formatNum(imagPart)}i');
      resultText = 'x = ${formatNum(realPart)} ± ${formatNum(imagPart)}i';
    }

    return StepByStepSolution(
      title: 'Quadratic Equation Solver',
      input: '${aStr}x² + ${bStr}x + $cStr = 0',
      steps: steps,
      result: resultText,
      data: {'a': a, 'b': b, 'c': c, 'discriminant': disc, 'vertexX': h, 'vertexY': k},
    );
  }

  /// Solves linear equation ax + b = c
  static StepByStepSolution solveLinearEquation({
    required double a,
    required double b,
    required double c,
  }) {
    final steps = <String>[];
    final aStr = formatNum(a);
    final bStr = formatNum(b);
    final cStr = formatNum(c);

    steps.add('Equation: ${aStr}x ${b >= 0 ? '+' : '-'} ${formatNum(b.abs())} = $cStr');

    if (a == 0) {
      if (b == c) {
        return StepByStepSolution(
          title: 'Linear Equation Solver',
          input: '$bStr = $cStr',
          steps: ['0x = 0', 'True for all real numbers x.'],
          result: 'Infinite solutions (all real numbers)',
        );
      } else {
        return StepByStepSolution(
          title: 'Linear Equation Solver',
          input: '$bStr = $cStr',
          steps: ['0x = ${formatNum(c - b)}', 'Contradiction: no value of x satisfies this equation.'],
          result: 'No solution',
        );
      }
    }

    final rhs = c - b;
    steps.add('Subtract $bStr from both sides: ${aStr}x = $cStr - ($bStr) = ${formatNum(rhs)}');
    final sol = rhs / a;
    steps.add('Divide both sides by $aStr: x = ${formatNum(rhs)} / $aStr = ${formatNum(sol)}');

    return StepByStepSolution(
      title: 'Linear Equation Solver',
      input: '${aStr}x + $bStr = $cStr',
      steps: steps,
      result: 'x = ${formatNum(sol)}',
      data: {'x': sol},
    );
  }

  /// Solves a 2x2 system of linear equations using Cramer's Rule:
  /// a₁x + b₁y = c₁
  /// a₂x + b₂y = c₂
  static StepByStepSolution solveLinearSystem2x2({
    required double a1,
    required double b1,
    required double c1,
    required double a2,
    required double b2,
    required double c2,
  }) {
    final steps = <String>[];
    steps.add('Equation 1: ${formatNum(a1)}x + ${formatNum(b1)}y = ${formatNum(c1)}');
    steps.add('Equation 2: ${formatNum(a2)}x + ${formatNum(b2)}y = ${formatNum(c2)}');

    // Determinants
    final det = a1 * b2 - a2 * b1;
    final detX = c1 * b2 - c2 * b1;
    final detY = a1 * c2 - a2 * c1;

    steps.add('Main Determinant: D = (${formatNum(a1)})(${formatNum(b2)}) - (${formatNum(a2)})(${formatNum(b1)}) = ${formatNum(det)}');

    if (det == 0) {
      if (detX == 0 && detY == 0) {
        steps.add('D = 0 and Dx = Dy = 0: The equations are coincident (same line).');
        return StepByStepSolution(
          title: 'System of Equations Solver (Cramer\'s Rule)',
          input: 'System of 2 Equations',
          steps: steps,
          result: 'Infinitely many solutions (dependent system)',
        );
      } else {
        steps.add('D = 0 and Dx ≠ 0: The equations represent parallel lines.');
        return StepByStepSolution(
          title: 'System of Equations Solver (Cramer\'s Rule)',
          input: 'System of 2 Equations',
          steps: steps,
          result: 'No solution (parallel lines)',
        );
      }
    }

    steps.add('X Determinant: Dx = (${formatNum(c1)})(${formatNum(b2)}) - (${formatNum(c2)})(${formatNum(b1)}) = ${formatNum(detX)}');
    steps.add('Y Determinant: Dy = (${formatNum(a1)})(${formatNum(c2)}) - (${formatNum(a2)})(${formatNum(c1)}) = ${formatNum(detY)}');

    final x = detX / det;
    final y = detY / det;

    steps.add('Calculate x = Dx / D = ${formatNum(detX)} / ${formatNum(det)} = ${formatNum(x)}');
    steps.add('Calculate y = Dy / D = ${formatNum(detY)} / ${formatNum(det)} = ${formatNum(y)}');

    return StepByStepSolution(
      title: 'System of Equations Solver (Cramer\'s Rule)',
      input: 'System of 2 Equations',
      steps: steps,
      result: 'x = ${formatNum(x)},  y = ${formatNum(y)}',
      data: {'x': x, 'y': y, 'D': det, 'Dx': detX, 'Dy': detY},
    );
  }

  // =========================================================================
  // GEOMETRY SOLVERS
  // =========================================================================

  /// Solves Pythagorean Theorem for right triangle: a² + b² = c²
  static StepByStepSolution solvePythagoras({
    double? a,
    double? b,
    double? c,
  }) {
    final steps = <String>[];

    if (a != null && b != null) {
      // Find hypotenuse c
      final cSq = a * a + b * b;
      final cVal = math.sqrt(cSq);
      final area = 0.5 * a * b;
      final perim = a + b + cVal;

      steps.add('Given legs: a = ${formatNum(a)}, b = ${formatNum(b)}');
      steps.add('Pythagorean formula: c² = a² + b²');
      steps.add('Substitute values: c² = (${formatNum(a)})² + (${formatNum(b)})² = ${formatNum(a * a)} + ${formatNum(b * b)} = ${formatNum(cSq)}');
      steps.add('Calculate hypotenuse: c = √(${formatNum(cSq)}) = ${formatNum(cVal)}');
      steps.add('Triangle Area = ½ · a · b = ½ · ${formatNum(a)} · ${formatNum(b)} = ${formatNum(area)}');
      steps.add('Perimeter = a + b + c = ${formatNum(perim)}');

      return StepByStepSolution(
        title: 'Pythagorean Theorem Solver',
        input: 'a = ${formatNum(a)}, b = ${formatNum(b)}',
        steps: steps,
        result: 'Hypotenuse c = ${formatNum(cVal)}',
        data: {'a': a, 'b': b, 'c': cVal, 'area': area, 'perimeter': perim},
      );
    } else if (c != null && a != null) {
      // Find leg b
      if (c <= a) {
        return StepByStepSolution(
          title: 'Pythagorean Theorem Solver',
          input: 'a = ${formatNum(a)}, c = ${formatNum(c)}',
          steps: ['Hypotenuse c must be strictly greater than leg a.'],
          result: 'Invalid triangle dimensions',
        );
      }
      final bSq = c * c - a * a;
      final bVal = math.sqrt(bSq);
      final area = 0.5 * a * bVal;

      steps.add('Given leg a = ${formatNum(a)} and hypotenuse c = ${formatNum(c)}');
      steps.add('Rearrange formula: b² = c² - a²');
      steps.add('Substitute values: b² = (${formatNum(c)})² - (${formatNum(a)})² = ${formatNum(c * c)} - ${formatNum(a * a)} = ${formatNum(bSq)}');
      steps.add('Calculate leg: b = √(${formatNum(bSq)}) = ${formatNum(bVal)}');
      steps.add('Triangle Area = ½ · a · b = ${formatNum(area)}');

      return StepByStepSolution(
        title: 'Pythagorean Theorem Solver',
        input: 'a = ${formatNum(a)}, c = ${formatNum(c)}',
        steps: steps,
        result: 'Leg b = ${formatNum(bVal)}',
        data: {'a': a, 'b': bVal, 'c': c, 'area': area},
      );
    } else if (c != null && b != null) {
      // Find leg a
      if (c <= b) {
        return StepByStepSolution(
          title: 'Pythagorean Theorem Solver',
          input: 'b = ${formatNum(b)}, c = ${formatNum(c)}',
          steps: ['Hypotenuse c must be strictly greater than leg b.'],
          result: 'Invalid triangle dimensions',
        );
      }
      final aSq = c * c - b * b;
      final aVal = math.sqrt(aSq);
      final area = 0.5 * aVal * b;

      steps.add('Given leg b = ${formatNum(b)} and hypotenuse c = ${formatNum(c)}');
      steps.add('Rearrange formula: a² = c² - b²');
      steps.add('Substitute values: a² = (${formatNum(c)})² - (${formatNum(b)})² = ${formatNum(c * c)} - ${formatNum(b * b)} = ${formatNum(aSq)}');
      steps.add('Calculate leg: a = √(${formatNum(aSq)}) = ${formatNum(aVal)}');
      steps.add('Triangle Area = ½ · a · b = ${formatNum(area)}');

      return StepByStepSolution(
        title: 'Pythagorean Theorem Solver',
        input: 'b = ${formatNum(b)}, c = ${formatNum(c)}',
        steps: steps,
        result: 'Leg a = ${formatNum(aVal)}',
        data: {'a': aVal, 'b': b, 'c': c, 'area': area},
      );
    }

    return StepByStepSolution(
      title: 'Pythagorean Theorem Solver',
      input: 'Insufficient parameters',
      steps: ['Please provide at least 2 sides (either a and b, or a and c, or b and c).'],
      result: 'N/A',
    );
  }

  /// Solves any triangle using Heron's Formula: A = √(s(s - a)(s - b)(s - c))
  static StepByStepSolution solveTriangleHeron({
    required double a,
    required double b,
    required double c,
  }) {
    final steps = <String>[];
    steps.add('Sides: a = ${formatNum(a)}, b = ${formatNum(b)}, c = ${formatNum(c)}');

    // Triangle inequality check
    if (a + b <= c || a + c <= b || b + c <= a) {
      steps.add('Triangle inequality failed: sum of any two sides must be strictly greater than the third side.');
      return StepByStepSolution(
        title: 'Heron\'s Triangle Area Solver',
        input: 'Sides $a, $b, $c',
        steps: steps,
        result: 'Invalid triangle: sides cannot form a closed triangle',
      );
    }

    final p = a + b + c;
    final s = p / 2;
    steps.add('Perimeter: P = a + b + c = ${formatNum(p)}');
    steps.add('Semiperimeter: s = P / 2 = ${formatNum(s)}');

    final diffA = s - a;
    final diffB = s - b;
    final diffC = s - c;
    steps.add('Differences: (s - a) = ${formatNum(diffA)},  (s - b) = ${formatNum(diffB)},  (s - c) = ${formatNum(diffC)}');

    final rad = s * diffA * diffB * diffC;
    final area = math.sqrt(rad);
    steps.add('Heron\'s Formula: Area = √(s · (s - a) · (s - b) · (s - c))');
    steps.add('Area = √(${formatNum(s)} · ${formatNum(diffA)} · ${formatNum(diffB)} · ${formatNum(diffC)}) = √(${formatNum(rad)}) = ${formatNum(area)}');

    return StepByStepSolution(
      title: 'Heron\'s Triangle Area Solver',
      input: 'Sides ${formatNum(a)}, ${formatNum(b)}, ${formatNum(c)}',
      steps: steps,
      result: 'Area = ${formatNum(area)}',
      data: {'area': area, 'perimeter': p, 'semiperimeter': s},
    );
  }

  /// Solves Circle properties: Area, Circumference, Diameter from radius
  static StepByStepSolution solveCircle({required double radius}) {
    final steps = <String>[];
    steps.add('Given Radius: r = ${formatNum(radius)}');

    final d = 2 * radius;
    final c = 2 * math.pi * radius;
    final a = math.pi * radius * radius;

    steps.add('Diameter: d = 2r = 2 · ${formatNum(radius)} = ${formatNum(d)}');
    steps.add('Circumference: C = 2πr = 2 · π · ${formatNum(radius)} ≈ ${formatNum(c)}');
    steps.add('Area: A = πr² = π · (${formatNum(radius)})² = π · ${formatNum(radius * radius)} ≈ ${formatNum(a)}');

    return StepByStepSolution(
      title: 'Circle Properties Solver',
      input: 'Radius r = ${formatNum(radius)}',
      steps: steps,
      result: 'Area ≈ ${formatNum(a)},  Circumference ≈ ${formatNum(c)}',
      data: {'radius': radius, 'diameter': d, 'circumference': c, 'area': a},
    );
  }

  /// Solves regular polygon: Area, Perimeter, Interior Angles
  static StepByStepSolution solveRegularPolygon({
    required int sides,
    required double sideLength,
  }) {
    final steps = <String>[];
    final n = sides;
    final s = sideLength;

    steps.add('Regular Polygon with n = $n sides, side length s = ${formatNum(s)}');
    final perim = n * s;
    steps.add('Perimeter: P = n · s = $n · ${formatNum(s)} = ${formatNum(perim)}');

    final intAngle = ((n - 2) * 180.0) / n;
    steps.add('Interior Angle = (n - 2) · 180° / n = ($n - 2) · 180° / $n = ${formatNum(intAngle)}°');

    final apothem = s / (2 * math.tan(math.pi / n));
    steps.add('Apothem: a = s / (2 · tan(π/n)) = ${formatNum(apothem)}');

    final area = (n * s * s) / (4 * math.tan(math.pi / n));
    steps.add('Area: A = ½ · P · a = ½ · ${formatNum(perim)} · ${formatNum(apothem)} = ${formatNum(area)}');

    return StepByStepSolution(
      title: 'Regular $n-gon Geometry Solver',
      input: 'n = $n sides, s = ${formatNum(s)}',
      steps: steps,
      result: 'Area ≈ ${formatNum(area)},  Interior Angle = ${formatNum(intAngle)}°',
      data: {'sides': n, 'sideLength': s, 'perimeter': perim, 'area': area, 'interiorAngle': intAngle},
    );
  }

  /// Solves coordinate geometry: Distance, Midpoint, Slope, Line Equation
  static StepByStepSolution solveCoordinates({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) {
    final steps = <String>[];
    steps.add('Point A: (${formatNum(x1)}, ${formatNum(y1)}),  Point B: (${formatNum(x2)}, ${formatNum(y2)})');

    final dx = x2 - x1;
    final dy = y2 - y1;
    final dist = math.sqrt(dx * dx + dy * dy);
    steps.add('Distance formula: d = √((x₂ - x₁)² + (y₂ - y₁)²);');
    steps.add('d = √((${formatNum(dx)})² + (${formatNum(dy)})²) = √(${formatNum(dx * dx + dy * dy)}) = ${formatNum(dist)}');

    final mx = (x1 + x2) / 2;
    final my = (y1 + y2) / 2;
    steps.add('Midpoint: M = ((x₁ + x₂)/2, (y₁ + y₂)/2) = (${formatNum(mx)}, ${formatNum(my)})');

    String slopeStr;
    String eqStr;
    if (dx == 0) {
      slopeStr = 'Undefined (vertical line)';
      eqStr = 'x = ${formatNum(x1)}';
      steps.add('Slope: Δx = 0, so line is vertical (slope is undefined).');
      steps.add('Line Equation: $eqStr');
    } else {
      final slope = dy / dx;
      slopeStr = formatNum(slope);
      final intercept = y1 - slope * x1;
      steps.add('Slope: m = (y₂ - y₁) / (x₂ - x₁) = ${formatNum(dy)} / ${formatNum(dx)} = $slopeStr');
      eqStr = 'y = ${slopeStr}x ${intercept >= 0 ? '+' : '-'} ${formatNum(intercept.abs())}';
      steps.add('Y-Intercept: b = y₁ - m·x₁ = ${formatNum(y1)} - ($slopeStr · ${formatNum(x1)}) = ${formatNum(intercept)}');
      steps.add('Equation: $eqStr');
    }

    return StepByStepSolution(
      title: 'Coordinate Geometry Solver',
      input: '(${formatNum(x1)}, ${formatNum(y1)}) to (${formatNum(x2)}, ${formatNum(y2)})',
      steps: steps,
      result: 'Distance = ${formatNum(dist)},  Midpoint = (${formatNum(mx)}, ${formatNum(my)})',
      data: {'distance': dist, 'midpointX': mx, 'midpointY': my, 'slope': slopeStr, 'equation': eqStr},
    );
  }

  // =========================================================================
  // TRIGONOMETRY SOLVERS
  // =========================================================================

  /// Solves Law of Cosines: c² = a² + b² - 2ab cos(C)
  static StepByStepSolution solveLawOfCosines({
    required double a,
    required double b,
    required double angleCDeg,
  }) {
    final steps = <String>[];
    steps.add('Given: side a = ${formatNum(a)}, side b = ${formatNum(b)}, included angle C = ${formatNum(angleCDeg)}°');

    final rad = angleCDeg * (math.pi / 180.0);
    final cosC = math.cos(rad);
    steps.add('Convert angle to radians: C ≈ ${formatNum(rad)} rad,  cos(C) ≈ ${formatNum(cosC)}');

    final cSq = a * a + b * b - 2 * a * b * cosC;
    final cVal = math.sqrt(math.max(0, cSq));
    steps.add('Law of Cosines: c² = a² + b² - 2ab·cos(C)');
    steps.add('c² = (${formatNum(a)})² + (${formatNum(b)})² - 2(${formatNum(a)})(${formatNum(b)})(${formatNum(cosC)})');
    steps.add('c² = ${formatNum(a * a)} + ${formatNum(b * b)} - ${formatNum(2 * a * b * cosC)} = ${formatNum(cSq)}');
    steps.add('c = √(${formatNum(cSq)}) ≈ ${formatNum(cVal)}');

    final area = 0.5 * a * b * math.sin(rad);
    steps.add('Triangle Area = ½ · a · b · sin(C) ≈ ${formatNum(area)}');

    return StepByStepSolution(
      title: 'Law of Cosines Solver',
      input: 'a = ${formatNum(a)}, b = ${formatNum(b)}, C = ${formatNum(angleCDeg)}°',
      steps: steps,
      result: 'Side c ≈ ${formatNum(cVal)},  Area ≈ ${formatNum(area)}',
      data: {'a': a, 'b': b, 'c': cVal, 'angleC': angleCDeg, 'area': area},
    );
  }

  /// Solves Law of Sines: a / sin(A) = b / sin(B) = c / sin(C)
  static StepByStepSolution solveLawOfSines({
    required double a,
    required double angleADeg,
    required double angleBDeg,
  }) {
    final steps = <String>[];
    steps.add('Given: side a = ${formatNum(a)}, angle A = ${formatNum(angleADeg)}°, angle B = ${formatNum(angleBDeg)}°');

    final angleCDeg = 180.0 - angleADeg - angleBDeg;
    if (angleCDeg <= 0) {
      return StepByStepSolution(
        title: 'Law of Sines Solver',
        input: 'A = $angleADeg°, B = $angleBDeg°',
        steps: ['Sum of angles A and B must be strictly less than 180°.'],
        result: 'Invalid triangle angles',
      );
    }

    steps.add('Third Angle: C = 180° - (A + B) = 180° - (${formatNum(angleADeg)}° + ${formatNum(angleBDeg)}°) = ${formatNum(angleCDeg)}°');

    final radA = angleADeg * (math.pi / 180.0);
    final radB = angleBDeg * (math.pi / 180.0);
    final radC = angleCDeg * (math.pi / 180.0);

    final sinA = math.sin(radA);
    final sinB = math.sin(radB);
    final sinC = math.sin(radC);

    final b = a * (sinB / sinA);
    final c = a * (sinC / sinA);

    steps.add('Law of Sines ratio: a / sin(A) = ${formatNum(a)} / ${formatNum(sinA)} ≈ ${formatNum(a / sinA)}');
    steps.add('Side b = a · sin(B) / sin(A) = ${formatNum(a)} · ${formatNum(sinB)} / ${formatNum(sinA)} ≈ ${formatNum(b)}');
    steps.add('Side c = a · sin(C) / sin(A) = ${formatNum(a)} · ${formatNum(sinC)} / ${formatNum(sinA)} ≈ ${formatNum(c)}');

    return StepByStepSolution(
      title: 'Law of Sines Solver',
      input: 'a = ${formatNum(a)}, A = ${formatNum(angleADeg)}°, B = ${formatNum(angleBDeg)}°',
      steps: steps,
      result: 'b ≈ ${formatNum(b)},  c ≈ ${formatNum(c)},  C = ${formatNum(angleCDeg)}°',
      data: {'a': a, 'b': b, 'c': c, 'angleA': angleADeg, 'angleB': angleBDeg, 'angleC': angleCDeg},
    );
  }

  // =========================================================================
  // CALCULUS SOLVERS
  // =========================================================================

  /// Differentiates a single variable polynomial expression symbolically term-by-term:
  /// e.g. "4x^3 - 5x^2 + 7x - 9" -> 12x^2 - 10x + 7
  static StepByStepSolution differentiatePolynomial(String rawInput) {
    final clean = rawInput.trim();
    final terms = _parsePolynomial(clean);

    final steps = <String>[];
    steps.add('Function: f(x) = $clean');
    steps.add('Apply Power Rule term-by-term: d/dx [c · xⁿ] = c · n · xⁿ⁻¹');

    final diffTerms = <_PolyTerm>[];
    for (final term in terms) {
      if (term.power == 0) {
        steps.add('d/dx [${formatNum(term.coeff)}] = 0  (derivative of a constant is 0)');
      } else {
        final newCoeff = term.coeff * term.power;
        final newPower = term.power - 1;
        steps.add('d/dx [${_formatTerm(term.coeff, term.power)}] = ${formatNum(term.coeff)} · ${term.power} · x^${term.power - 1} = ${_formatTerm(newCoeff, newPower)}');
        diffTerms.add(_PolyTerm(coeff: newCoeff, power: newPower));
      }
    }

    final diffStr = _formatPolynomial(diffTerms);
    steps.add('Combine all differentiated terms:');

    // Second derivative as extra bonus
    final secondDiffTerms = <_PolyTerm>[];
    for (final term in diffTerms) {
      if (term.power > 0) {
        secondDiffTerms.add(_PolyTerm(coeff: term.coeff * term.power, power: term.power - 1));
      }
    }
    final secondDiffStr = _formatPolynomial(secondDiffTerms);

    return StepByStepSolution(
      title: 'Symbolic Polynomial Derivative',
      input: 'f(x) = $clean',
      steps: steps,
      result: 'f\'(x) = $diffStr  |  f\'\'(x) = $secondDiffStr',
      data: {'firstDerivative': diffStr, 'secondDerivative': secondDiffStr},
    );
  }

  /// Integrates a polynomial symbolically (indefinite + optional definite integral):
  /// e.g. "6x^2 + 4x - 5" -> 2x^3 + 2x^2 - 5x + C
  static StepByStepSolution integratePolynomial(
    String rawInput, {
    double? lowerLimit,
    double? upperLimit,
  }) {
    final clean = rawInput.trim();
    final terms = _parsePolynomial(clean);

    final steps = <String>[];
    steps.add('Integrand: f(x) = $clean');
    steps.add('Apply Reverse Power Rule term-by-term: ∫ c · xⁿ dx = (c / (n + 1)) · xⁿ⁺¹');

    final intTerms = <_PolyTerm>[];
    for (final term in terms) {
      final newPower = term.power + 1;
      final newCoeff = term.coeff / newPower;
      steps.add('∫ [${_formatTerm(term.coeff, term.power)}] dx = (${formatNum(term.coeff)} / $newPower) · x^$newPower = ${_formatTerm(newCoeff, newPower)}');
      intTerms.add(_PolyTerm(coeff: newCoeff, power: newPower));
    }

    final antiderivativeStr = '${_formatPolynomial(intTerms)} + C';
    steps.add('Indefinite Integral: F(x) = $antiderivativeStr');

    String finalResult = antiderivativeStr;

    if (lowerLimit != null && upperLimit != null) {
      steps.add('── Definite Integral Evaluation ──');
      steps.add('Limits: a = ${formatNum(lowerLimit)}, b = ${formatNum(upperLimit)}');
      steps.add('Fundamental Theorem of Calculus: ∫ₐᵇ f(x) dx = F(b) - F(a)');

      final valB = _evaluatePolynomialTerms(intTerms, upperLimit);
      final valA = _evaluatePolynomialTerms(intTerms, lowerLimit);
      final netVal = valB - valA;

      steps.add('F(${formatNum(upperLimit)}) = ${formatNum(valB)}');
      steps.add('F(${formatNum(lowerLimit)}) = ${formatNum(valA)}');
      steps.add('Net Result = ${formatNum(valB)} - (${formatNum(valA)}) = ${formatNum(netVal)}');

      finalResult = formatNum(netVal);
    }

    return StepByStepSolution(
      title: lowerLimit != null ? 'Definite Integral Solver' : 'Symbolic Indefinite Integral',
      input: '∫ $clean dx',
      steps: steps,
      result: finalResult,
      data: {'antiderivative': antiderivativeStr},
    );
  }

  // --- Internal Polynomial Parsing Helpers ---

  static List<_PolyTerm> _parsePolynomial(String input) {
    var s = input.replaceAll(' ', '');
    // Insert '+' before '-' if not at start
    s = s.replaceAll('-', '+-');
    if (s.startsWith('+')) s = s.substring(1);

    final parts = s.split('+').where((p) => p.isNotEmpty).toList();
    final list = <_PolyTerm>[];

    for (final raw in parts) {
      final t = _parseTerm(raw);
      if (t != null) list.add(t);
    }
    return list;
  }

  static _PolyTerm? _parseTerm(String raw) {
    if (raw.isEmpty) return null;
    if (!raw.contains('x')) {
      final val = double.tryParse(raw);
      if (val != null) return _PolyTerm(coeff: val, power: 0);
      return null;
    }

    // Contains 'x'
    double coeff = 1.0;
    int power = 1;

    final xIdx = raw.indexOf('x');
    final coeffPart = raw.substring(0, xIdx);
    if (coeffPart.isEmpty) {
      coeff = 1.0;
    } else if (coeffPart == '+') {
      coeff = 1.0;
    } else if (coeffPart == '-') {
      coeff = -1.0;
    } else {
      coeff = double.tryParse(coeffPart) ?? 1.0;
    }

    final afterX = raw.substring(xIdx + 1);
    if (afterX.isEmpty) {
      power = 1;
    } else if (afterX.startsWith('^')) {
      power = int.tryParse(afterX.substring(1)) ?? 1;
    }

    return _PolyTerm(coeff: coeff, power: power);
  }

  static String _formatTerm(double coeff, int power) {
    final cStr = formatNum(coeff);
    if (power == 0) return cStr;
    final prefix = (coeff == 1.0) ? '' : (coeff == -1.0 ? '-' : cStr);
    if (power == 1) return '${prefix}x';
    return '${prefix}x^$power';
  }

  static String _formatPolynomial(List<_PolyTerm> terms) {
    if (terms.isEmpty) return '0';
    final buffer = StringBuffer();
    for (int i = 0; i < terms.length; i++) {
      final t = terms[i];
      if (t.coeff == 0) continue;
      final termStr = _formatTerm(t.coeff.abs(), t.power);
      if (buffer.isEmpty) {
        if (t.coeff < 0) buffer.write('-');
        buffer.write(termStr);
      } else {
        buffer.write(t.coeff >= 0 ? ' + ' : ' - ');
        buffer.write(termStr);
      }
    }
    return buffer.isEmpty ? '0' : buffer.toString();
  }

  static double _evaluatePolynomialTerms(List<_PolyTerm> terms, double x) {
    double total = 0.0;
    for (final t in terms) {
      total += t.coeff * math.pow(x, t.power);
    }
    return total;
  }

  // =========================================================================
  // SYMBOLIC ALGEBRAIC IDENTITIES & FORMULAS (0ms REAL-TIME SOLVER)
  // =========================================================================

  /// Solves or factors algebraic identities, formulas, and expansions in 0ms locally
  static String? solveAlgebraicIdentity(String rawInput) {
    var text = rawInput.trim();
    if (text.endsWith('=')) {
      text = text.substring(0, text.length - 1).trim();
    } else if (text.endsWith('?')) {
      text = text.substring(0, text.length - 1).trim();
    }

    if (text.isEmpty) return null;

    // Normalize characters:
    var norm = text
        .replaceAll(' ', '')
        .replaceAll('³', '^3')
        .replaceAll('²', '^2')
        .replaceAll('×', '*')
        .replaceAll('·', '*')
        .toLowerCase();

    // 1. Difference of Cubes: a^3 - b^3 or x^3 - y^3
    final diffCubesVar = RegExp(r'^([a-z])\^3-([a-z])\^3$');
    final m1 = diffCubesVar.firstMatch(norm);
    if (m1 != null) {
      final a = m1.group(1)!;
      final b = m1.group(2)!;
      return '($a - $b)($a² + $a$b + $b²)';
    }

    // 2. Sum of Cubes: a^3 + b^3 or x^3 + y^3
    final sumCubesVar = RegExp(r'^([a-z])\^3\+([a-z])\^3$');
    final m2 = sumCubesVar.firstMatch(norm);
    if (m2 != null) {
      final a = m2.group(1)!;
      final b = m2.group(2)!;
      return '($a + $b)($a² - $a$b + $b²)';
    }

    // 3. Difference of Cubes with constant: x^3 - 8, x^3 - 27, x^3 - 1
    final diffCubesNum = RegExp(r'^([a-z])\^3-(\d+)$');
    final m3 = diffCubesNum.firstMatch(norm);
    if (m3 != null) {
      final v = m3.group(1)!;
      final n = int.tryParse(m3.group(2)!);
      if (n != null && n > 0) {
        final c = math.pow(n, 1.0 / 3.0).round();
        if (c * c * c == n) {
          final c2 = c * c;
          final mid = (c == 1) ? v : '$c$v';
          return '($v - $c)($v² + $mid + $c2)';
        }
      }
    }

    // 4. Sum of Cubes with constant: x^3 + 8, x^3 + 27, x^3 + 1
    final sumCubesNum = RegExp(r'^([a-z])\^3\+(\d+)$');
    final m4 = sumCubesNum.firstMatch(norm);
    if (m4 != null) {
      final v = m4.group(1)!;
      final n = int.tryParse(m4.group(2)!);
      if (n != null && n > 0) {
        final c = math.pow(n, 1.0 / 3.0).round();
        if (c * c * c == n) {
          final c2 = c * c;
          final mid = (c == 1) ? v : '$c$v';
          return '($v + $c)($v² - $mid + $c2)';
        }
      }
    }

    // 5. Difference of Squares: a^2 - b^2 or x^2 - y^2
    final diffSquaresVar = RegExp(r'^([a-z])\^2-([a-z])\^2$');
    final m5 = diffSquaresVar.firstMatch(norm);
    if (m5 != null) {
      final a = m5.group(1)!;
      final b = m5.group(2)!;
      return '($a - $b)($a + $b)';
    }

    // 6. Difference of Squares with constant: x^2 - 4, x^2 - 9, x^2 - 16, x^2 - 25
    final diffSquaresNum = RegExp(r'^([a-z])\^2-(\d+)$');
    final m6 = diffSquaresNum.firstMatch(norm);
    if (m6 != null) {
      final v = m6.group(1)!;
      final n = int.tryParse(m6.group(2)!);
      if (n != null && n > 0) {
        final r = math.sqrt(n).round();
        if (r * r == n) {
          return '($v - $r)($v + $r)';
        }
      }
    }

    // 7. Square of Binomial: (a + b)^2 or (a - b)^2
    final sqBinomialVar = RegExp(r'^\(([a-z])([+-])([a-z])\)\^2$');
    final m7 = sqBinomialVar.firstMatch(norm);
    if (m7 != null) {
      final a = m7.group(1)!;
      final sign = m7.group(2)!;
      final b = m7.group(3)!;
      return '$a² $sign 2$a$b + $b²';
    }

    // 8. Square of Binomial with constant: (x + 3)^2, (x - 5)^2
    final sqBinomialNum = RegExp(r'^\(([a-z])([+-])(\d+)\)\^2$');
    final m8 = sqBinomialNum.firstMatch(norm);
    if (m8 != null) {
      final v = m8.group(1)!;
      final sign = m8.group(2)!;
      final c = int.parse(m8.group(3)!);
      final twoC = 2 * c;
      final c2 = c * c;
      return '$v² $sign ${twoC}$v + $c2';
    }

    // 9. Cube of Binomial: (a + b)^3 or (a - b)^3
    final cubeBinomialVar = RegExp(r'^\(([a-z])([+-])([a-z])\)\^3$');
    final m9 = cubeBinomialVar.firstMatch(norm);
    if (m9 != null) {
      final a = m9.group(1)!;
      final sign = m9.group(2)!;
      final b = m9.group(3)!;
      if (sign == '+') {
        return '$a³ + 3$a²$b + 3$a$b² + $b³';
      } else {
        return '$a³ - 3$a²$b + 3$a$b² - $b³';
      }
    }

    // 10. Cube of Binomial with constant: (x + 2)^3, (x - 1)^3
    final cubeBinomialNum = RegExp(r'^\(([a-z])([+-])(\d+)\)\^3$');
    final m10 = cubeBinomialNum.firstMatch(norm);
    if (m10 != null) {
      final v = m10.group(1)!;
      final sign = m10.group(2)!;
      final c = int.parse(m10.group(3)!);
      final threeC = 3 * c;
      final threeC2 = 3 * c * c;
      final c3 = c * c * c;
      if (sign == '+') {
        return '$v³ + ${threeC}$v² + ${threeC2}$v + $c3';
      } else {
        return '$v³ - ${threeC}$v² + ${threeC2}$v - $c3';
      }
    }

    // 11. Trigonometric identities
    if (norm == 'sin^2(x)+cos^2(x)' || norm == 'sin^2x+cos^2x' || norm == 'cos^2(x)+sin^2(x)' || norm == 'cos^2x+sin^2x') {
      return '1';
    }
    if (norm == '1+tan^2(x)' || norm == '1+tan^2x') {
      return 'sec²(x)';
    }
    if (norm == '1+cot^2(x)' || norm == '1+cot^2x') {
      return 'csc²(x)';
    }
    if (norm == 'tan(x)' || norm == 'tanx') {
      return 'sin(x) / cos(x)';
    }
    if (norm == 'sin(2x)' || norm == 'sin(2*x)') {
      return '2sin(x)cos(x)';
    }
    if (norm == 'cos(2x)' || norm == 'cos(2*x)') {
      return 'cos²(x) - sin²(x)';
    }

    // 12. Basic Calculus Derivatives d/dx(...)
    if (norm.startsWith('d/dx')) {
      var expr = norm.substring(4);
      if (expr.startsWith('(') && expr.endsWith(')')) {
        expr = expr.substring(1, expr.length - 1);
      }
      if (expr == 'x') return '1';
      if (expr == 'x^2') return '2x';
      if (expr == 'x^3') return '3x²';
      if (expr == 'sinx' || expr == 'sin(x)') return 'cos(x)';
      if (expr == 'cosx' || expr == 'cos(x)') return '-sin(x)';
      if (expr == 'tanx' || expr == 'tan(x)') return 'sec²(x)';
      if (expr == 'e^x') return 'e^x';
      if (expr == 'lnx' || expr == 'ln(x)') return '1/x';
      final powMatch = RegExp(r'^x\^(\d+)$').firstMatch(expr);
      if (powMatch != null) {
        final p = int.parse(powMatch.group(1)!);
        return '${p}x^${p - 1}';
      }
    }

    // 13. Basic Calculus Integrals int(...)dx
    if (norm.startsWith('int') || norm.startsWith('∫')) {
      var expr = norm.startsWith('int') ? norm.substring(3) : norm.substring(1);
      if (expr.endsWith('dx')) {
        expr = expr.substring(0, expr.length - 2);
      }
      if (expr.startsWith('(') && expr.endsWith(')')) {
        expr = expr.substring(1, expr.length - 1);
      }
      if (expr == '1' || expr.isEmpty) return 'x + C';
      if (expr == 'x') return 'x² / 2 + C';
      if (expr == 'x^2') return 'x³ / 3 + C';
      if (expr == 'sinx' || expr == 'sin(x)') return '-cos(x) + C';
      if (expr == 'cosx' || expr == 'cos(x)') return 'sin(x) + C';
      if (expr == 'e^x') return 'e^x + C';
      if (expr == '1/x') return 'ln|x| + C';
      final powMatch = RegExp(r'^x\^(\d+)$').firstMatch(expr);
      if (powMatch != null) {
        final p = int.parse(powMatch.group(1)!);
        return 'x^${p + 1} / ${p + 1} + C';
      }
    }

    // 14. Pythagoras identity: a^2 + b^2
    if (norm == 'a^2+b^2') {
      return 'c²';
    }

    return null;
  }
}

class _PolyTerm {
  final double coeff;
  final int power;
  const _PolyTerm({required this.coeff, required this.power});
}
