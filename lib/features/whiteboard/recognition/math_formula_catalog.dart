enum MathCategory {
  algebra('Algebra'),
  geometry('Geometry'),
  trigonometry('Trigonometry'),
  calculus('Calculus');

  final String label;
  const MathCategory(this.label);
}

class MathFormula {
  final String id;
  final String title;
  final MathCategory category;
  final String formula;
  final String description;
  final String variables;
  final String example;
  final String? solverType; // 'quadratic', 'pythagoras', 'derivative', etc.

  const MathFormula({
    required this.id,
    required this.title,
    required this.category,
    required this.formula,
    required this.description,
    required this.variables,
    required this.example,
    this.solverType,
  });
}

class MathFormulaCatalog {
  static const List<MathFormula> allFormulas = [
    // ==========================================
    // ALGEBRA
    // ==========================================
    MathFormula(
      id: 'alg-quadratic',
      title: 'Quadratic Formula',
      category: MathCategory.algebra,
      formula: 'x = (-b ± √(b² - 4ac)) / (2a)',
      description:
          'Solves any quadratic equation ax² + bx + c = 0 for real or complex roots.',
      variables:
          'a = quadratic coefficient, b = linear coefficient, c = constant',
      example: '2x² - 4x - 6 = 0  =>  x = 3 or x = -1',
      solverType: 'quadratic',
    ),
    MathFormula(
      id: 'alg-discriminant',
      title: 'Discriminant',
      category: MathCategory.algebra,
      formula: 'Δ = b² - 4ac',
      description:
          'Determines the nature of roots (Δ > 0: two real roots; Δ = 0: one real root; Δ < 0: two complex roots).',
      variables: 'a, b, c from ax² + bx + c = 0',
      example: 'b=4, a=1, c=4 => Δ = 16 - 16 = 0 (one real root)',
      solverType: 'quadratic',
    ),
    MathFormula(
      id: 'alg-linear-system',
      title: 'System of 2 Linear Equations (Cramer\'s Rule)',
      category: MathCategory.algebra,
      formula:
          'x = (c₁b₂ - c₂b₁) / (a₁b₂ - a₂b₁),  y = (a₁c₂ - a₂c₁) / (a₁b₂ - a₂b₁)',
      description:
          'Finds the unique intersection (x, y) of two linear equations a₁x + b₁y = c₁ and a₂x + b₂y = c₂.',
      variables: 'a₁, b₁, c₁ (equation 1) and a₂, b₂, c₂ (equation 2)',
      example: 'x + y = 10, 2x - y = 5  =>  x = 5, y = 5',
      solverType: 'linear_system',
    ),
    MathFormula(
      id: 'alg-diff-squares',
      title: 'Difference of Squares',
      category: MathCategory.algebra,
      formula: 'a² - b² = (a - b)(a + b)',
      description:
          'Factoring formula for the difference between two perfect squares.',
      variables: 'a, b = any real expressions',
      example: 'x² - 16 = (x - 4)(x + 4)',
    ),
    MathFormula(
      id: 'alg-square-binomial',
      title: 'Square of a Binomial',
      category: MathCategory.algebra,
      formula: '(a ± b)² = a² ± 2ab + b²',
      description: 'Expansion of binomial sums and differences squared.',
      variables: 'a, b = terms in binomial',
      example: '(x + 5)² = x² + 10x + 25',
    ),
    MathFormula(
      id: 'alg-cubes',
      title: 'Sum and Difference of Cubes',
      category: MathCategory.algebra,
      formula: 'a³ ± b³ = (a ± b)(a² ∓ ab + b²)',
      description: 'Factoring identity for sums and differences of cubes.',
      variables: 'a, b = cube roots',
      example: 'x³ - 8 = (x - 2)(x² + 2x + 4)',
    ),
    MathFormula(
      id: 'alg-exponents',
      title: 'Laws of Exponents',
      category: MathCategory.algebra,
      formula: 'xᵃ · xᵇ = xᵃ⁺ᵇ,   xᵃ / xᵇ = xᵃ⁻ᵇ,   (xᵃ)ᵇ = xᵃᵇ',
      description:
          'Fundamental algebraic rules for combining powers with equal bases.',
      variables: 'x = base, a, b = exponents',
      example: '2³ · 2⁴ = 2⁷ = 128',
    ),
    MathFormula(
      id: 'alg-logarithms',
      title: 'Laws of Logarithms',
      category: MathCategory.algebra,
      formula:
          'log(xy) = log x + log y,   log(x/y) = log x - log y,   log(xᵏ) = k·log x',
      description:
          'Core identities used to simplify and solve exponential and logarithmic equations.',
      variables: 'x, y > 0, k = power',
      example: 'log₁₀(1000) = log₁₀(10³) = 3',
    ),
    MathFormula(
      id: 'alg-arithmetic-seq',
      title: 'Arithmetic Progression (AP)',
      category: MathCategory.algebra,
      formula: 'aₙ = a₁ + (n - 1)d,   Sₙ = n/2 · [2a₁ + (n - 1)d]',
      description:
          'Calculates the n-th term and partial sum of an arithmetic sequence.',
      variables: 'a₁ = first term, d = common difference, n = term index',
      example: 'a₁=3, d=4, n=5 => a₅ = 3 + 4(4) = 19, S₅ = 55',
    ),
    MathFormula(
      id: 'alg-geometric-seq',
      title: 'Geometric Progression (GP)',
      category: MathCategory.algebra,
      formula: 'aₙ = a₁ · rⁿ⁻¹,   Sₙ = a₁(1 - rⁿ) / (1 - r)',
      description: 'Calculates the n-th term and sum of a geometric sequence.',
      variables: 'a₁ = first term, r = common ratio (r ≠ 1), n = term count',
      example: 'a₁=2, r=3, n=4 => a₄ = 2(27) = 54, S₄ = 80',
    ),

    // ==========================================
    // GEOMETRY
    // ==========================================
    MathFormula(
      id: 'geom-pythagoras',
      title: 'Pythagorean Theorem',
      category: MathCategory.geometry,
      formula: 'a² + b² = c²   =>   c = √(a² + b²)',
      description:
          'Relates the legs (a, b) and hypotenuse (c) of any right-angled triangle.',
      variables: 'a = vertical leg, b = horizontal leg, c = hypotenuse',
      example: 'a = 3, b = 4 => c = √(9 + 16) = 5',
      solverType: 'pythagoras',
    ),
    MathFormula(
      id: 'geom-triangle-area',
      title: 'Triangle Area & Heron\'s Formula',
      category: MathCategory.geometry,
      formula:
          'A = ½ · b · h  or  A = √(s(s - a)(s - b)(s - c)),   s = (a + b + c)/2',
      description:
          'Standard base-height area or Heron\'s formula given all 3 sides.',
      variables:
          'b = base, h = height, or a, b, c = side lengths, s = semiperimeter',
      example: 'sides 3, 4, 5 => s = 6, A = √(6·3·2·1) = 6',
      solverType: 'triangle_area',
    ),
    MathFormula(
      id: 'geom-circle',
      title: 'Circle Area and Circumference',
      category: MathCategory.geometry,
      formula: 'A = π · r²,   C = 2 · π · r,   d = 2r',
      description: 'Calculates area, circumference, and diameter from radius.',
      variables: 'r = radius, d = diameter, π ≈ 3.14159',
      example: 'r = 7 => C ≈ 43.98, A ≈ 153.94',
      solverType: 'circle',
    ),
    MathFormula(
      id: 'geom-regular-polygon',
      title: 'Regular Polygon (Pentagon, Hexagon, Octagon)',
      category: MathCategory.geometry,
      formula:
          'Area = (n · s²) / (4 · tan(π / n)),   Interior Angle = (n - 2)·180° / n',
      description:
          'Calculates area, perimeter, and interior angles for regular n-sided polygons.',
      variables: 'n = number of sides (5, 6, 8...), s = side length',
      example: 'Hexagon (n=6, s=10) => Area = 259.81, Angle = 120°',
      solverType: 'polygon',
    ),
    MathFormula(
      id: 'geom-trapezoid',
      title: 'Trapezoid Area',
      category: MathCategory.geometry,
      formula: 'A = ½ · (a + b) · h',
      description:
          'Area of a trapezoid with parallel bases a and b, and height h.',
      variables: 'a, b = parallel bases, h = perpendicular height',
      example: 'a = 6, b = 10, h = 4 => A = ½(16)(4) = 32',
    ),
    MathFormula(
      id: 'geom-cylinder',
      title: 'Cylinder Volume & Surface Area',
      category: MathCategory.geometry,
      formula: 'V = π · r² · h,   A = 2π·r·h + 2π·r²',
      description:
          'Volume and total surface area of a right circular cylinder.',
      variables: 'r = radius, h = height',
      example: 'r = 3, h = 5 => V = 45π ≈ 141.37',
      solverType: 'cylinder',
    ),
    MathFormula(
      id: 'geom-cone',
      title: 'Cone Volume & Slant Height',
      category: MathCategory.geometry,
      formula: 'V = ⅓ · π · r² · h,   s = √(r² + h²)',
      description: 'Volume and slant height of a right circular cone.',
      variables: 'r = radius, h = vertical height, s = slant height',
      example: 'r = 3, h = 4 => s = 5, V = 12π ≈ 37.70',
      solverType: 'cone',
    ),
    MathFormula(
      id: 'geom-sphere',
      title: 'Sphere Volume & Surface Area',
      category: MathCategory.geometry,
      formula: 'V = (4/3) · π · r³,   A = 4 · π · r²',
      description: 'Volume and surface area of a sphere.',
      variables: 'r = radius',
      example: 'r = 3 => V = 36π ≈ 113.10, A = 36π ≈ 113.10',
      solverType: 'sphere',
    ),
    MathFormula(
      id: 'geom-distance-midpoint',
      title: 'Coordinate Distance & Midpoint',
      category: MathCategory.geometry,
      formula:
          'd = √((x₂ - x₁)² + (y₂ - y₁)²),   M = ((x₁ + x₂)/2, (y₁ + y₂)/2)',
      description:
          'Euclidean distance and midpoint coordinates between two 2D points.',
      variables: '(x₁, y₁) = Point 1, (x₂, y₂) = Point 2',
      example: '(1, 2) and (4, 6) => d = √(9 + 16) = 5, M = (2.5, 4)',
      solverType: 'coordinate',
    ),
    MathFormula(
      id: 'geom-line-slope',
      title: 'Slope-Intercept Line Equation',
      category: MathCategory.geometry,
      formula: 'y = mx + b,   m = (y₂ - y₁) / (x₂ - x₁)',
      description:
          'Equation of a straight line with slope m and y-intercept b.',
      variables: 'm = slope, b = y-intercept',
      example: 'm = 2, passes (1, 3) => y = 2x + 1',
    ),

    // ==========================================
    // TRIGONOMETRY
    // ==========================================
    MathFormula(
      id: 'trig-ratios',
      title: 'Trigonometric Ratios (SOH CAH TOA)',
      category: MathCategory.trigonometry,
      formula: 'sin θ = Opp/Hyp,   cos θ = Adj/Hyp,   tan θ = Opp/Adj',
      description: 'Fundamental ratios for right-angled triangles.',
      variables: 'Opp = opposite leg, Adj = adjacent leg, Hyp = hypotenuse',
      example: 'Opp=3, Adj=4, Hyp=5 => sin θ = 0.6, cos θ = 0.8, tan θ = 0.75',
      solverType: 'trig_triangle',
    ),
    MathFormula(
      id: 'trig-pythagorean-identities',
      title: 'Pythagorean Trigonometric Identities',
      category: MathCategory.trigonometry,
      formula: 'sin²θ + cos²θ = 1,   1 + tan²θ = sec²θ,   1 + cot²θ = csc²θ',
      description: 'Core identities derived directly from the unit circle.',
      variables: 'θ = angle in degrees or radians',
      example: 'sin(30°) = 0.5 => cos(30°) = √(1 - 0.25) = √0.75 ≈ 0.866',
    ),
    MathFormula(
      id: 'trig-law-of-sines',
      title: 'Law of Sines',
      category: MathCategory.trigonometry,
      formula: 'a / sin A = b / sin B = c / sin C = 2R',
      description:
          'Relates sides and opposite angles for any triangle (oblique or right).',
      variables:
          'a, b, c = side lengths; A, B, C = opposite angles; R = circumradius',
      example: 'a=10, A=30°, B=45° => b = 10 · sin(45°)/sin(30°) ≈ 14.14',
      solverType: 'law_of_sines',
    ),
    MathFormula(
      id: 'trig-law-of-cosines',
      title: 'Law of Cosines',
      category: MathCategory.trigonometry,
      formula: 'c² = a² + b² - 2ab · cos C',
      description:
          'Generalization of Pythagoras to any triangle given two sides and included angle.',
      variables: 'a, b = adjacent sides, C = included angle, c = opposite side',
      example: 'a = 5, b = 7, C = 60° => c = √(25 + 49 - 35) = √39 ≈ 6.24',
      solverType: 'law_of_cosines',
    ),
    MathFormula(
      id: 'trig-double-angle',
      title: 'Double Angle Formulas',
      category: MathCategory.trigonometry,
      formula:
          'sin(2θ) = 2 sin θ cos θ,   cos(2θ) = cos²θ - sin²θ = 2cos²θ - 1',
      description: 'Expresses trig functions of 2θ in terms of functions of θ.',
      variables: 'θ = angle',
      example:
          'θ=30° => sin(60°) = 2·sin(30°)·cos(30°) = 2(0.5)(0.866) = 0.866',
    ),
    MathFormula(
      id: 'trig-sum-difference',
      title: 'Sum and Difference Angle Formulas',
      category: MathCategory.trigonometry,
      formula:
          'sin(A ± B) = sin A cos B ± cos A sin B,   cos(A ± B) = cos A cos B ∓ sin A sin B',
      description: 'Computes trig values of combined angles.',
      variables: 'A, B = individual angles',
      example: 'sin(75°) = sin(45° + 30°) = (√6 + √2)/4 ≈ 0.9659',
    ),

    // ==========================================
    // CALCULUS
    // ==========================================
    MathFormula(
      id: 'calc-power-rule-diff',
      title: 'Derivative: Power Rule',
      category: MathCategory.calculus,
      formula: 'd/dx [c · xⁿ] = c · n · xⁿ⁻¹',
      description:
          'Differentiation power rule for polynomials and rational powers.',
      variables: 'c = constant scalar, n = exponent, x = independent variable',
      example: 'd/dx [5x³] = 15x²',
      solverType: 'derivative',
    ),
    MathFormula(
      id: 'calc-product-rule',
      title: 'Derivative: Product Rule',
      category: MathCategory.calculus,
      formula: 'd/dx [u · v] = u\'v + uv\'',
      description:
          'Differentiation rule for multiplying two differentiable functions.',
      variables: 'u(x), v(x) = component functions',
      example: 'd/dx [x² · sin x] = 2x sin x + x² cos x',
    ),
    MathFormula(
      id: 'calc-quotient-rule',
      title: 'Derivative: Quotient Rule',
      category: MathCategory.calculus,
      formula: 'd/dx [u / v] = (u\'v - uv\') / v²',
      description: 'Differentiation rule for the ratio of two functions.',
      variables: 'u(x) = numerator, v(x) = denominator (v ≠ 0)',
      example: 'd/dx [sin x / x] = (x cos x - sin x) / x²',
    ),
    MathFormula(
      id: 'calc-chain-rule',
      title: 'Derivative: Chain Rule',
      category: MathCategory.calculus,
      formula: 'd/dx [f(g(x))] = f\'(g(x)) · g\'(x)',
      description: 'Derivative of composite nested functions.',
      variables: 'f = outer function, g = inner function',
      example: 'd/dx [sin(x²)] = cos(x²) · 2x',
    ),
    MathFormula(
      id: 'calc-standard-derivatives',
      title: 'Standard Derivative Identities',
      category: MathCategory.calculus,
      formula:
          'd/dx[sin x] = cos x,   d/dx[cos x] = -sin x,   d/dx[eˣ] = eˣ,   d/dx[ln x] = 1/x',
      description: 'Core derivatives of elementary transcendental functions.',
      variables: 'x = variable',
      example: 'd/dx [3eˣ + 2sin x] = 3eˣ + 2cos x',
    ),
    MathFormula(
      id: 'calc-power-rule-integ',
      title: 'Indefinite Integral: Power Rule',
      category: MathCategory.calculus,
      formula: '∫ c · xⁿ dx = (c / (n + 1)) · xⁿ⁺¹ + C   (for n ≠ -1)',
      description:
          'Reverse power rule for anti-derivatives and indefinite integration.',
      variables:
          'c = constant scalar, n = power (n ≠ -1), C = constant of integration',
      example: '∫ 6x² dx = (6/3)x³ + C = 2x³ + C',
      solverType: 'integral',
    ),
    MathFormula(
      id: 'calc-definite-integral',
      title: 'Definite Integral & FTC',
      category: MathCategory.calculus,
      formula: '∫ₐᵇ f(x) dx = F(b) - F(a),   where F\'(x) = f(x)',
      description:
          'Fundamental Theorem of Calculus: net area under curve between x = a and x = b.',
      variables: 'a = lower limit, b = upper limit, F(x) = antiderivative',
      example: '∫₀² 3x² dx = [x³]₀² = 8 - 0 = 8',
      solverType: 'integral',
    ),
    MathFormula(
      id: 'calc-by-parts',
      title: 'Integration by Parts',
      category: MathCategory.calculus,
      formula: '∫ u dv = u·v - ∫ v du',
      description:
          'Calculus identity for integrating products of algebraic and transcendental functions.',
      variables: 'u = differentiable part, dv = integrable part',
      example: '∫ x eˣ dx = x eˣ - ∫ eˣ dx = x eˣ - eˣ + C',
    ),
    MathFormula(
      id: 'calc-limits',
      title: 'Fundamental Limits',
      category: MathCategory.calculus,
      formula: 'lim (x→0) [sin x / x] = 1,   lim (x→0) [(1 + x)¹/ˣ] = e',
      description: 'Standard foundational limits for calculus and derivatives.',
      variables: 'x approaches limit point',
      example: 'lim (x→0) [sin(3x) / x] = 3',
      solverType: 'limit',
    ),
  ];

  static List<MathFormula> getByCategory(MathCategory cat) {
    return allFormulas.where((f) => f.category == cat).toList();
  }

  static List<MathFormula> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return allFormulas;
    return allFormulas.where((f) {
      return f.title.toLowerCase().contains(q) ||
          f.formula.toLowerCase().contains(q) ||
          f.description.toLowerCase().contains(q) ||
          f.category.label.toLowerCase().contains(q);
    }).toList();
  }
}
