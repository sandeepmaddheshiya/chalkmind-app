import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/features/whiteboard/recognition/math_formula_catalog.dart';
import 'package:boardflow/features/whiteboard/recognition/universal_math_engine.dart';

void main() {
  group('MathFormulaCatalog tests', () {
    test('Contains formulas across all 4 categories', () {
      expect(MathFormulaCatalog.allFormulas.length, greaterThanOrEqualTo(25));

      final algebra = MathFormulaCatalog.getByCategory(MathCategory.algebra);
      final geometry = MathFormulaCatalog.getByCategory(MathCategory.geometry);
      final trig = MathFormulaCatalog.getByCategory(MathCategory.trigonometry);
      final calculus = MathFormulaCatalog.getByCategory(MathCategory.calculus);

      expect(algebra, isNotEmpty);
      expect(geometry, isNotEmpty);
      expect(trig, isNotEmpty);
      expect(calculus, isNotEmpty);
    });

    test('Search finds specific formulas by keywords', () {
      final quad = MathFormulaCatalog.search('quadratic');
      expect(quad.any((f) => f.id == 'alg-quadratic'), isTrue);

      final pyth = MathFormulaCatalog.search('pythagorean');
      expect(pyth.any((f) => f.id == 'geom-pythagoras'), isTrue);

      final diff = MathFormulaCatalog.search('power rule');
      expect(diff.any((f) => f.id == 'calc-power-rule-diff'), isTrue);
    });
  });

  group('UniversalMathEngine Algebra tests', () {
    test('Quadratic equation with two real roots: x² - 5x + 6 = 0', () {
      final sol = UniversalMathEngine.solveQuadratic(a: 1, b: -5, c: 6);
      expect(sol.result, contains('x = 3'));
      expect(sol.result, contains('x = 2'));
      expect(sol.steps.length, greaterThanOrEqualTo(4));
      expect(sol.data['discriminant'], 1);
    });

    test('Quadratic equation with single double root: x² - 4x + 4 = 0', () {
      final sol = UniversalMathEngine.solveQuadratic(a: 1, b: -4, c: 4);
      expect(sol.result, contains('x = 2 (double root)'));
      expect(sol.data['discriminant'], 0);
    });

    test('Quadratic equation with complex conjugate roots: x² + 4 = 0', () {
      final sol = UniversalMathEngine.solveQuadratic(a: 1, b: 0, c: 4);
      expect(sol.result, contains('± 2i'));
      expect(sol.data['discriminant'], -16);
    });

    test('Linear equation: 3x + 12 = 27', () {
      final sol = UniversalMathEngine.solveLinearEquation(a: 3, b: 12, c: 27);
      expect(sol.result, 'x = 5');
      expect(sol.data['x'], 5);
    });

    test('System of 2 linear equations: x + y = 10 and 2x - y = 5', () {
      final sol = UniversalMathEngine.solveLinearSystem2x2(
        a1: 1, b1: 1, c1: 10,
        a2: 2, b2: -1, c2: 5,
      );
      expect(sol.data['x'], 5);
      expect(sol.data['y'], 5);
      expect(sol.result, contains('x = 5'));
      expect(sol.result, contains('y = 5'));
    });
  });

  group('UniversalMathEngine Geometry tests', () {
    test('Pythagorean theorem: legs 3 and 4 => c = 5', () {
      final sol = UniversalMathEngine.solvePythagoras(a: 3, b: 4);
      expect(sol.result, 'Hypotenuse c = 5');
      expect(sol.data['c'], 5);
      expect(sol.data['area'], 6);
      expect(sol.data['perimeter'], 12);
    });

    test('Pythagorean theorem: hypotenuse 5 and leg 3 => leg b = 4', () {
      final sol = UniversalMathEngine.solvePythagoras(a: 3, c: 5);
      expect(sol.result, 'Leg b = 4');
      expect(sol.data['b'], 4);
    });

    test('Heron\'s formula: sides 3, 4, 5 => area = 6', () {
      final sol = UniversalMathEngine.solveTriangleHeron(a: 3, b: 4, c: 5);
      expect(sol.result, 'Area = 6');
      expect(sol.data['area'], 6);
      expect(sol.data['perimeter'], 12);
    });

    test('Circle properties: r = 7', () {
      final sol = UniversalMathEngine.solveCircle(radius: 7);
      expect(sol.data['diameter'], 14);
      expect((sol.data['area'] as double).round(), 154);
      expect((sol.data['circumference'] as double).round(), 44);
    });

    test('Regular Hexagon (n=6, s=10)', () {
      final sol = UniversalMathEngine.solveRegularPolygon(sides: 6, sideLength: 10);
      expect(sol.data['interiorAngle'], 120);
      expect(sol.data['perimeter'], 60);
      expect((sol.data['area'] as double).round(), 260);
    });

    test('Coordinate distance and midpoint: (1, 2) to (4, 6)', () {
      final sol = UniversalMathEngine.solveCoordinates(x1: 1, y1: 2, x2: 4, y2: 6);
      expect(sol.data['distance'], 5);
      expect(sol.data['midpointX'], 2.5);
      expect(sol.data['midpointY'], 4);
    });
  });

  group('UniversalMathEngine Trigonometry tests', () {
    test('Law of Cosines: a=5, b=7, C=60° => c = √39 ≈ 6.245', () {
      final sol = UniversalMathEngine.solveLawOfCosines(a: 5, b: 7, angleCDeg: 60);
      expect(sol.data['c'], closeTo(6.245, 0.01));
      expect(sol.steps, isNotEmpty);
    });

    test('Law of Sines: a=10, A=30°, B=45° => b ≈ 14.14', () {
      final sol = UniversalMathEngine.solveLawOfSines(a: 10, angleADeg: 30, angleBDeg: 45);
      expect(sol.data['angleC'], 105);
      expect(sol.data['b'], closeTo(14.142, 0.01));
    });
  });

  group('UniversalMathEngine Calculus tests', () {
    test('Polynomial derivative: 4x^3 - 5x^2 + 7x - 9 => 12x^2 - 10x + 7', () {
      final sol = UniversalMathEngine.differentiatePolynomial('4x^3 - 5x^2 + 7x - 9');
      expect(sol.data['firstDerivative'], '12x^2 - 10x + 7');
      expect(sol.data['secondDerivative'], '24x - 10');
      expect(sol.formattedBoardText, contains('f\'(x) = 12x^2 - 10x + 7'));
    });

    test('Indefinite integral: 6x^2 + 4x - 5 => 2x^3 + 2x^2 - 5x + C', () {
      final sol = UniversalMathEngine.integratePolynomial('6x^2 + 4x - 5');
      expect(sol.data['antiderivative'], '2x^3 + 2x^2 - 5x + C');
    });

    test('Definite integral: ∫₀² 3x² dx = [x³]₀² = 8', () {
      final sol = UniversalMathEngine.integratePolynomial('3x^2', lowerLimit: 0, upperLimit: 2);
      expect(sol.result, '8');
    });
  });

  group('UniversalMathEngine Symbolic Algebraic Identity Solver tests (0ms)', () {
    test('Difference of cubes: a^3 - b^3 = (a - b)(a² + ab + b²)', () {
      final res1 = UniversalMathEngine.solveAlgebraicIdentity('a^3 - b^3 =');
      expect(res1, '(a - b)(a² + ab + b²)');

      final res2 = UniversalMathEngine.solveAlgebraicIdentity('a³ - b³');
      expect(res2, '(a - b)(a² + ab + b²)');

      final res3 = UniversalMathEngine.solveAlgebraicIdentity('x^3 - y^3 =');
      expect(res3, '(x - y)(x² + xy + y²)');

      final res4 = UniversalMathEngine.solveAlgebraicIdentity('x^3 - 8');
      expect(res4, '(x - 2)(x² + 2x + 4)');
    });

    test('Sum of cubes: a^3 + b^3 = (a + b)(a² - ab + b²)', () {
      final res1 = UniversalMathEngine.solveAlgebraicIdentity('a^3 + b^3 =');
      expect(res1, '(a + b)(a² - ab + b²)');

      final res2 = UniversalMathEngine.solveAlgebraicIdentity('x^3 + 27 =');
      expect(res2, '(x + 3)(x² - 3x + 9)');
    });

    test('Difference of squares: a^2 - b^2 and x^2 - 9', () {
      final res1 = UniversalMathEngine.solveAlgebraicIdentity('a^2 - b^2 =');
      expect(res1, '(a - b)(a + b)');

      final res2 = UniversalMathEngine.solveAlgebraicIdentity('x^2 - 16 =');
      expect(res2, '(x - 4)(x + 4)');
    });

    test('Binomial squares: (a + b)^2 and (x - 5)^2', () {
      final res1 = UniversalMathEngine.solveAlgebraicIdentity('(a + b)^2 =');
      expect(res1, 'a² + 2ab + b²');

      final res2 = UniversalMathEngine.solveAlgebraicIdentity('(x - 3)^2 =');
      expect(res2, 'x² - 6x + 9');
    });

    test('Binomial cubes: (a - b)^3', () {
      final res = UniversalMathEngine.solveAlgebraicIdentity('(a - b)^3 =');
      expect(res, 'a³ - 3a²b + 3ab² - b³');
    });

    test('Trigonometry identities: sin^2(x) + cos^2(x) = 1', () {
      expect(UniversalMathEngine.solveAlgebraicIdentity('sin^2(x) + cos^2(x) ='), '1');
      expect(UniversalMathEngine.solveAlgebraicIdentity('1 + tan^2(x) ='), 'sec²(x)');
      expect(UniversalMathEngine.solveAlgebraicIdentity('sin(2x) ='), '2sin(x)cos(x)');
    });

    test('Calculus derivatives and integrals: d/dx(x^3) and int(x^2)dx', () {
      expect(UniversalMathEngine.solveAlgebraicIdentity('d/dx(x^3) ='), '3x²');
      expect(UniversalMathEngine.solveAlgebraicIdentity('d/dx(sin(x)) ='), 'cos(x)');
      expect(UniversalMathEngine.solveAlgebraicIdentity('int(x^2)dx ='), 'x³ / 3 + C');
      expect(UniversalMathEngine.solveAlgebraicIdentity('int(cos(x))dx ='), 'sin(x) + C');
    });

    test('Non-identity inputs return null safely', () {
      expect(UniversalMathEngine.solveAlgebraicIdentity('hello teacher'), isNull);
      expect(UniversalMathEngine.solveAlgebraicIdentity('x + y ='), isNull);
    });
  });
}
