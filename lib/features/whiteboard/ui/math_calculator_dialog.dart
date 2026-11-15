import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/plot_model.dart';
import '../recognition/math_evaluator.dart';
import '../recognition/math_formula_catalog.dart';
import '../recognition/math_function_parser.dart';
import '../recognition/universal_math_engine.dart';
import '../rendering/plot_painter.dart';
import '../state/whiteboard_notifier.dart';

class MathCalculatorDialog extends ConsumerStatefulWidget {
  const MathCalculatorDialog({super.key});

  @override
  ConsumerState<MathCalculatorDialog> createState() =>
      _MathCalculatorDialogState();
}

class _MathCalculatorDialogState extends ConsumerState<MathCalculatorDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- Tab 1: Calculator State ---
  final TextEditingController _calcController = TextEditingController();
  MathEvaluationResult? _evalResult;

  // --- Tab 2: Function Grapher State ---
  final TextEditingController _graphController = TextEditingController(
    text: 'y = x^2 - 4',
  );
  MathFunction? _graphFunction;
  PlotObject _graphPlot = const PlotObject(
    id: 'preview',
    equation: 'y = x^2 - 4',
    rect: Rect.fromLTWH(0, 0, 480, 240),
  );
  double _graphLastScale = 1.0;

  // --- Tab 3: Solver State ---
  MathCategory _solverCategory = MathCategory.algebra;
  String _selectedSolver = 'quadratic';

  // Algebra Controllers
  final _quadA = TextEditingController(text: '1');
  final _quadB = TextEditingController(text: '-5');
  final _quadC = TextEditingController(text: '6');

  final _linA = TextEditingController(text: '3');
  final _linB = TextEditingController(text: '12');
  final _linC = TextEditingController(text: '27');

  final _sysA1 = TextEditingController(text: '1');
  final _sysB1 = TextEditingController(text: '1');
  final _sysC1 = TextEditingController(text: '10');
  final _sysA2 = TextEditingController(text: '2');
  final _sysB2 = TextEditingController(text: '-1');
  final _sysC2 = TextEditingController(text: '5');

  // Geometry Controllers
  final _pythA = TextEditingController(text: '3');
  final _pythB = TextEditingController(text: '4');
  final _heronA = TextEditingController(text: '3');
  final _heronB = TextEditingController(text: '4');
  final _heronC = TextEditingController(text: '5');
  final _circleR = TextEditingController(text: '7');
  final _polySides = TextEditingController(text: '6');
  final _polySideLen = TextEditingController(text: '10');
  final _coordX1 = TextEditingController(text: '1');
  final _coordY1 = TextEditingController(text: '2');
  final _coordX2 = TextEditingController(text: '4');
  final _coordY2 = TextEditingController(text: '6');

  // Trig Controllers
  final _cosA = TextEditingController(text: '5');
  final _cosB = TextEditingController(text: '7');
  final _cosAngle = TextEditingController(text: '60');
  final _sinSideA = TextEditingController(text: '10');
  final _sinAngleA = TextEditingController(text: '30');
  final _sinAngleB = TextEditingController(text: '45');

  // Calculus Controllers
  final _diffPoly = TextEditingController(text: '4x^3 - 5x^2 + 7x - 9');
  final _intPoly = TextEditingController(text: '6x^2 + 4x - 5');

  StepByStepSolution? _currentSolution;

  // --- Tab 4: Formula Catalog State ---
  final TextEditingController _formulaSearchController =
      TextEditingController();
  MathCategory? _selectedFormulaCategory;
  List<MathFormula> _filteredFormulas = MathFormulaCatalog.allFormulas;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _calcController.addListener(_onCalcChanged);
    _formulaSearchController.addListener(_onSearchChanged);
    _graphFunction = MathFunctionParser.parse(_graphController.text);
    _graphController.addListener(_onGraphChanged);
    _recomputeSolver();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _calcController.dispose();
    _formulaSearchController.dispose();
    _graphController.dispose();

    _quadA.dispose();
    _quadB.dispose();
    _quadC.dispose();
    _linA.dispose();
    _linB.dispose();
    _linC.dispose();
    _sysA1.dispose();
    _sysB1.dispose();
    _sysC1.dispose();
    _sysA2.dispose();
    _sysB2.dispose();
    _sysC2.dispose();

    _pythA.dispose();
    _pythB.dispose();
    _heronA.dispose();
    _heronB.dispose();
    _heronC.dispose();
    _circleR.dispose();
    _polySides.dispose();
    _polySideLen.dispose();
    _coordX1.dispose();
    _coordY1.dispose();
    _coordX2.dispose();
    _coordY2.dispose();

    _cosA.dispose();
    _cosB.dispose();
    _cosAngle.dispose();
    _sinSideA.dispose();
    _sinAngleA.dispose();
    _sinAngleB.dispose();

    _diffPoly.dispose();
    _intPoly.dispose();

    super.dispose();
  }

  void _onGraphChanged() {
    final text = _graphController.text.trim();
    setState(() {
      _graphFunction = MathFunctionParser.parse(text);
      _graphPlot = _graphPlot.copyWith(
        equation: text.isNotEmpty ? text : 'y = x',
      );
    });
  }

  void _selectGraphPreset(String equation) {
    _graphController.text = equation;
    setState(() {
      _graphFunction = MathFunctionParser.parse(equation);
      _graphPlot = _graphPlot.copyWith(equation: equation).resetView();
    });
  }

  void _onCalcChanged() {
    final text = _calcController.text;
    final res = MathEvaluator.evaluate(text);
    setState(() {
      _evalResult = res;
    });
  }

  void _onSearchChanged() {
    final q = _formulaSearchController.text;
    var list = MathFormulaCatalog.search(q);
    if (_selectedFormulaCategory != null) {
      list = list.where((f) => f.category == _selectedFormulaCategory).toList();
    }
    setState(() {
      _filteredFormulas = list;
    });
  }

  void _appendSymbol(String symbol) {
    final current = _calcController.text;
    final selection = _calcController.selection;

    if (selection.isValid && selection.start >= 0) {
      final newText = current.replaceRange(
        selection.start,
        selection.end,
        symbol,
      );
      _calcController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + symbol.length,
        ),
      );
    } else {
      _calcController.text = current + symbol;
    }
  }

  void _recomputeSolver() {
    StepByStepSolution? sol;
    try {
      if (_selectedSolver == 'quadratic') {
        final a = double.tryParse(_quadA.text) ?? 1.0;
        final b = double.tryParse(_quadB.text) ?? 0.0;
        final c = double.tryParse(_quadC.text) ?? 0.0;
        sol = UniversalMathEngine.solveQuadratic(a: a, b: b, c: c);
      } else if (_selectedSolver == 'linear') {
        final a = double.tryParse(_linA.text) ?? 1.0;
        final b = double.tryParse(_linB.text) ?? 0.0;
        final c = double.tryParse(_linC.text) ?? 0.0;
        sol = UniversalMathEngine.solveLinearEquation(a: a, b: b, c: c);
      } else if (_selectedSolver == 'linear_system') {
        final a1 = double.tryParse(_sysA1.text) ?? 1.0;
        final b1 = double.tryParse(_sysB1.text) ?? 1.0;
        final c1 = double.tryParse(_sysC1.text) ?? 0.0;
        final a2 = double.tryParse(_sysA2.text) ?? 1.0;
        final b2 = double.tryParse(_sysB2.text) ?? -1.0;
        final c2 = double.tryParse(_sysC2.text) ?? 0.0;
        sol = UniversalMathEngine.solveLinearSystem2x2(
          a1: a1,
          b1: b1,
          c1: c1,
          a2: a2,
          b2: b2,
          c2: c2,
        );
      } else if (_selectedSolver == 'pythagoras') {
        final a = double.tryParse(_pythA.text) ?? 3.0;
        final b = double.tryParse(_pythB.text) ?? 4.0;
        sol = UniversalMathEngine.solvePythagoras(a: a, b: b);
      } else if (_selectedSolver == 'triangle_area') {
        final a = double.tryParse(_heronA.text) ?? 3.0;
        final b = double.tryParse(_heronB.text) ?? 4.0;
        final c = double.tryParse(_heronC.text) ?? 5.0;
        sol = UniversalMathEngine.solveTriangleHeron(a: a, b: b, c: c);
      } else if (_selectedSolver == 'circle') {
        final r = double.tryParse(_circleR.text) ?? 7.0;
        sol = UniversalMathEngine.solveCircle(radius: r);
      } else if (_selectedSolver == 'polygon') {
        final n = int.tryParse(_polySides.text) ?? 6;
        final s = double.tryParse(_polySideLen.text) ?? 10.0;
        sol = UniversalMathEngine.solveRegularPolygon(sides: n, sideLength: s);
      } else if (_selectedSolver == 'coordinate') {
        final x1 = double.tryParse(_coordX1.text) ?? 1.0;
        final y1 = double.tryParse(_coordY1.text) ?? 2.0;
        final x2 = double.tryParse(_coordX2.text) ?? 4.0;
        final y2 = double.tryParse(_coordY2.text) ?? 6.0;
        sol = UniversalMathEngine.solveCoordinates(
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
        );
      } else if (_selectedSolver == 'law_of_cosines') {
        final a = double.tryParse(_cosA.text) ?? 5.0;
        final b = double.tryParse(_cosB.text) ?? 7.0;
        final ang = double.tryParse(_cosAngle.text) ?? 60.0;
        sol = UniversalMathEngine.solveLawOfCosines(a: a, b: b, angleCDeg: ang);
      } else if (_selectedSolver == 'law_of_sines') {
        final a = double.tryParse(_sinSideA.text) ?? 10.0;
        final angA = double.tryParse(_sinAngleA.text) ?? 30.0;
        final angB = double.tryParse(_sinAngleB.text) ?? 45.0;
        sol = UniversalMathEngine.solveLawOfSines(
          a: a,
          angleADeg: angA,
          angleBDeg: angB,
        );
      } else if (_selectedSolver == 'derivative') {
        sol = UniversalMathEngine.differentiatePolynomial(_diffPoly.text);
      } else if (_selectedSolver == 'integral') {
        sol = UniversalMathEngine.integratePolynomial(_intPoly.text);
      }
    } catch (_) {}

    setState(() {
      _currentSolution = sol;
    });
  }

  void _openSolverForFormula(MathFormula formula) {
    if (formula.solverType != null) {
      setState(() {
        _solverCategory = formula.category;
        _selectedSolver = formula.solverType!;
        _recomputeSolver();
        _tabController.animateTo(1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 680,
        height: 640,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.functions_rounded,
                    color: primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Teacher Math & Formula Center',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Universal solver for Arithmetic, Algebra, Geometry, Trig & Calculus',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tab bar
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF12141A) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: isDark
                    ? Colors.grey.shade400
                    : Colors.grey.shade600,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.calculate_rounded, size: 18),
                    text: 'Fast Calculator',
                  ),
                  Tab(
                    icon: Icon(Icons.show_chart_rounded, size: 18),
                    text: 'Function Grapher',
                  ),
                  Tab(
                    icon: Icon(Icons.psychology_alt_rounded, size: 18),
                    text: 'Step-by-Step Solvers',
                  ),
                  Tab(
                    icon: Icon(Icons.menu_book_rounded, size: 18),
                    text: 'Formula Catalog',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFastCalculatorTab(isDark, primaryColor),
                  _buildFunctionGrapherTab(isDark, primaryColor),
                  _buildStepByStepSolverTab(isDark, primaryColor),
                  _buildFormulaCatalogTab(isDark, primaryColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 1: Fast Calculator
  // =========================================================================

  Widget _buildFastCalculatorTab(bool isDark, Color primaryColor) {
    final symbols = [
      '7',
      '8',
      '9',
      '÷',
      '(',
      ')',
      '4',
      '5',
      '6',
      '×',
      '^',
      '√',
      '1',
      '2',
      '3',
      '-',
      '%',
      'sin(',
      '0',
      '.',
      '=',
      '+',
      'cos(',
      'tan(',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Input TextField
        TextField(
          controller: _calcController,
          autofocus: false,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          decoration: InputDecoration(
            hintText: 'e.g. 15 * 8, sqrt(144) + 6, 25% of 600, sin(30)',
            hintStyle: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.normal,
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF12141A) : Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Live Output
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF12141A) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _evalResult != null
                  ? primaryColor
                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              width: _evalResult != null ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live Result:',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _evalResult != null ? '= ${_evalResult!.resultText}' : '—',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _evalResult != null ? primaryColor : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Keypad
        Expanded(
          child: GridView.count(
            crossAxisCount: 6,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.5,
            children: symbols.map((sym) {
              final isSpecial =
                  sym == '=' ||
                  sym == '+' ||
                  sym == '-' ||
                  sym == '×' ||
                  sym == '÷';
              return Material(
                color: isSpecial
                    ? primaryColor.withValues(alpha: 0.15)
                    : (isDark ? const Color(0xFF282C37) : Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    if (sym == '=') {
                      _onCalcChanged();
                    } else {
                      _appendSymbol(sym);
                    }
                  },
                  child: Center(
                    child: Text(
                      sym,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isSpecial ? primaryColor : null,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _calcController.clear(),
                child: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                icon: const Icon(Icons.add_to_photos_rounded, size: 18),
                label: const Text('Insert on Board'),
                onPressed: _evalResult == null
                    ? null
                    : () {
                        ref
                            .read(whiteboardControllerProvider.notifier)
                            .insertMathCalculation(_calcController.text);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Inserted "${_evalResult!.fullEquation}" on canvas',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =========================================================================
  // TAB 2: Step-by-Step Solvers
  // =========================================================================

  Widget _buildStepByStepSolverTab(bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: MathCategory.values.map((cat) {
              final isSel = _solverCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat.label),
                  selected: isSel,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _solverCategory = cat;
                        // Select default solver for this category
                        if (cat == MathCategory.algebra) {
                          _selectedSolver = 'quadratic';
                        }
                        if (cat == MathCategory.geometry) {
                          _selectedSolver = 'pythagoras';
                        }
                        if (cat == MathCategory.trigonometry) {
                          _selectedSolver = 'law_of_cosines';
                        }
                        if (cat == MathCategory.calculus) {
                          _selectedSolver = 'derivative';
                        }
                        _recomputeSolver();
                      });
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),

        // Sub-problem selector
        _buildProblemSelector(primaryColor),
        const SizedBox(height: 10),

        // Parameter inputs based on selected solver
        _buildParameterInputs(),
        const SizedBox(height: 12),

        // Live Step-by-Step Derivation Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14171E) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              ),
            ),
            child: _currentSolution == null
                ? const Center(child: Text('Enter parameters to compute steps'))
                : ListView(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _currentSolution!.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: primaryColor,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Verified Steps',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      ..._currentSolution!.steps.map(
                        (st) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '• ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Expanded(
                                child: Text(
                                  st,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 16),
                      Text(
                        'Result: ${_currentSolution!.result}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.post_add_rounded, size: 18),
                label: const Text('Insert Working on Board'),
                onPressed: _currentSolution == null
                    ? null
                    : () {
                        ref
                            .read(whiteboardControllerProvider.notifier)
                            .insertStepByStepWorking(
                              _currentSolution!.formattedBoardText,
                            );
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Inserted ${_currentSolution!.title} steps on canvas',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProblemSelector(Color primaryColor) {
    List<DropdownMenuItem<String>> items = [];

    if (_solverCategory == MathCategory.algebra) {
      items = const [
        DropdownMenuItem(
          value: 'quadratic',
          child: Text('Quadratic Equation (ax² + bx + c = 0)'),
        ),
        DropdownMenuItem(
          value: 'linear',
          child: Text('Linear Equation (ax + b = c)'),
        ),
        DropdownMenuItem(
          value: 'linear_system',
          child: Text('2x2 System of Equations (Cramer\'s Rule)'),
        ),
      ];
    } else if (_solverCategory == MathCategory.geometry) {
      items = const [
        DropdownMenuItem(
          value: 'pythagoras',
          child: Text('Pythagorean Theorem (a² + b² = c²)'),
        ),
        DropdownMenuItem(
          value: 'triangle_area',
          child: Text('Heron\'s Formula for Triangle Area'),
        ),
        DropdownMenuItem(
          value: 'circle',
          child: Text('Circle Area & Circumference'),
        ),
        DropdownMenuItem(
          value: 'polygon',
          child: Text('Regular Polygon (Pentagon, Hexagon, Octagon)'),
        ),
        DropdownMenuItem(
          value: 'coordinate',
          child: Text('Coordinate Distance & Midpoint'),
        ),
      ];
    } else if (_solverCategory == MathCategory.trigonometry) {
      items = const [
        DropdownMenuItem(
          value: 'law_of_cosines',
          child: Text('Law of Cosines (c² = a² + b² - 2ab cos C)'),
        ),
        DropdownMenuItem(
          value: 'law_of_sines',
          child: Text('Law of Sines (a/sin A = b/sin B = c/sin C)'),
        ),
      ];
    } else {
      items = const [
        DropdownMenuItem(
          value: 'derivative',
          child: Text('Symbolic Derivative (Power Rule)'),
        ),
        DropdownMenuItem(
          value: 'integral',
          child: Text('Symbolic Indefinite & Definite Integral'),
        ),
      ];
    }

    return DropdownButtonFormField<String>(
      // Keyed so external changes (category chips, formula catalog) rebuild
      // the field with the new initial value.
      key: ValueKey(_selectedSolver),
      initialValue: _selectedSolver,
      decoration: InputDecoration(
        labelText: 'Select Topic / Formula',
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items: items,
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedSolver = val;
            _recomputeSolver();
          });
        }
      },
    );
  }

  Widget _buildParameterInputs() {
    if (_selectedSolver == 'quadratic') {
      return Row(
        children: [
          _miniField('a', _quadA),
          const SizedBox(width: 8),
          _miniField('b', _quadB),
          const SizedBox(width: 8),
          _miniField('c', _quadC),
        ],
      );
    } else if (_selectedSolver == 'linear') {
      return Row(
        children: [
          _miniField('a', _linA),
          const SizedBox(width: 8),
          _miniField('b', _linB),
          const SizedBox(width: 8),
          _miniField('c', _linC),
        ],
      );
    } else if (_selectedSolver == 'linear_system') {
      return Column(
        children: [
          Row(
            children: [
              _miniField('a₁', _sysA1),
              const SizedBox(width: 6),
              _miniField('b₁', _sysB1),
              const SizedBox(width: 6),
              _miniField('c₁', _sysC1),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _miniField('a₂', _sysA2),
              const SizedBox(width: 6),
              _miniField('b₂', _sysB2),
              const SizedBox(width: 6),
              _miniField('c₂', _sysC2),
            ],
          ),
        ],
      );
    } else if (_selectedSolver == 'pythagoras') {
      return Row(
        children: [
          _miniField('Leg a', _pythA),
          const SizedBox(width: 8),
          _miniField('Leg b', _pythB),
        ],
      );
    } else if (_selectedSolver == 'triangle_area') {
      return Row(
        children: [
          _miniField('Side a', _heronA),
          const SizedBox(width: 6),
          _miniField('Side b', _heronB),
          const SizedBox(width: 6),
          _miniField('Side c', _heronC),
        ],
      );
    } else if (_selectedSolver == 'circle') {
      return _miniField('Radius (r)', _circleR);
    } else if (_selectedSolver == 'polygon') {
      return Row(
        children: [
          _miniField('Sides (n)', _polySides),
          const SizedBox(width: 8),
          _miniField('Side Length (s)', _polySideLen),
        ],
      );
    } else if (_selectedSolver == 'coordinate') {
      return Row(
        children: [
          _miniField('x₁', _coordX1),
          const SizedBox(width: 6),
          _miniField('y₁', _coordY1),
          const SizedBox(width: 6),
          _miniField('x₂', _coordX2),
          const SizedBox(width: 6),
          _miniField('y₂', _coordY2),
        ],
      );
    } else if (_selectedSolver == 'law_of_cosines') {
      return Row(
        children: [
          _miniField('Side a', _cosA),
          const SizedBox(width: 8),
          _miniField('Side b', _cosB),
          const SizedBox(width: 8),
          _miniField('Angle C (°)', _cosAngle),
        ],
      );
    } else if (_selectedSolver == 'law_of_sines') {
      return Row(
        children: [
          _miniField('Side a', _sinSideA),
          const SizedBox(width: 8),
          _miniField('Angle A (°)', _sinAngleA),
          const SizedBox(width: 8),
          _miniField('Angle B (°)', _sinAngleB),
        ],
      );
    } else if (_selectedSolver == 'derivative') {
      return _miniField('Polynomial f(x)', _diffPoly, isText: true);
    } else if (_selectedSolver == 'integral') {
      return _miniField('Integrand f(x)', _intPoly, isText: true);
    }
    return const SizedBox.shrink();
  }

  Widget _miniField(
    String label,
    TextEditingController controller, {
    bool isText = false,
  }) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: isText
            ? TextInputType.text
            : const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
        onChanged: (_) => _recomputeSolver(),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 3: Formula Catalog
  // =========================================================================

  Widget _buildFormulaCatalogTab(bool isDark, Color primaryColor) {
    return Column(
      children: [
        // Search bar
        TextField(
          controller: _formulaSearchController,
          decoration: InputDecoration(
            hintText:
                'Search formulas (e.g. quadratic, Pythagoras, derivative, sine)...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            filled: true,
            fillColor: isDark ? const Color(0xFF14171E) : Colors.grey.shade100,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: _selectedFormulaCategory == null,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _selectedFormulaCategory = null;
                        _onSearchChanged();
                      });
                    }
                  },
                ),
              ),
              ...MathCategory.values.map((cat) {
                final isSel = _selectedFormulaCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cat.label),
                    selected: isSel,
                    onSelected: (val) {
                      setState(() {
                        _selectedFormulaCategory = val ? cat : null;
                        _onSearchChanged();
                      });
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Formula List
        Expanded(
          child: _filteredFormulas.isEmpty
              ? const Center(child: Text('No matching formulas found'))
              : ListView.builder(
                  itemCount: _filteredFormulas.length,
                  itemBuilder: (context, index) {
                    final f = _filteredFormulas[index];
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isDark
                          ? const Color(0xFF14171E)
                          : Colors.grey.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  f.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    f.category.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Formula box
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E222B)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey.shade700
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Text(
                                f.formula,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),

                            Text(
                              f.description,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Example: ${f.example}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Actions
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (f.solverType != null)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Solve with this',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    onPressed: () => _openSolverForFormula(f),
                                  ),
                                const SizedBox(width: 8),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.add_to_photos_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Insert Formula',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  onPressed: () {
                                    final boardText =
                                        '${f.title}\n${f.formula}\n${f.variables}';
                                    ref
                                        .read(
                                          whiteboardControllerProvider.notifier,
                                        )
                                        .insertStepByStepWorking(boardText);
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Inserted "${f.title}" on canvas',
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB: Function Grapher (Desmos-Style Real-Time Plotter)
  // =========================================================================

  Widget _buildFunctionGrapherTab(bool isDark, Color primaryColor) {
    const presets = [
      ('y = x^2 - 4', 'Parabola'),
      ('y = sin(x)', 'Sine'),
      ('y = 2x + 1', 'Linear'),
      ('y = x^3 - 3x', 'Cubic'),
      ('x^2 + y^2 = 25', 'Circle'),
      ('y = cos(x)', 'Cosine'),
      ('y = 1 / x', 'Hyperbola'),
      ('y = sqrt(x)', 'Square Root'),
      ('y = -x^2 + 5', 'Inverted'),
      ('y = 2^x', 'Exponential'),
    ];

    final keyPoints =
        _graphFunction?.findKeyPoints(_graphPlot.xMin, _graphPlot.xMax) ?? [];
    final rootsCount = keyPoints.where((k) => k.pointType == 'root').length;
    final vertexCount = keyPoints.where((k) => k.pointType == 'vertex').length;
    final yIntCount = keyPoints
        .where((k) => k.pointType == 'y_intercept')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Equation Input Bar
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _graphController,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.show_chart_rounded, size: 20),
                  hintText:
                      'e.g. y = x^2 - 4, y = sin(x), y = 2x + 1, x^2 + y^2 = 25',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    fontFamily: 'sans-serif',
                    fontWeight: FontWeight.normal,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF12141A)
                      : Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _graphController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => _graphController.clear(),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _graphFunction != null
                    ? const Color(0xFF059669).withValues(alpha: 0.15)
                    : Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _graphFunction != null
                      ? const Color(0xFF059669).withValues(alpha: 0.4)
                      : Colors.red.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _graphFunction != null
                        ? Icons.check_circle_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 16,
                    color: _graphFunction != null
                        ? const Color(0xFF059669)
                        : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _graphFunction != null ? 'Valid' : 'Check syntax',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _graphFunction != null
                          ? const Color(0xFF059669)
                          : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 2. Preset Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: presets.map((preset) {
              final isSel = _graphController.text.trim() == preset.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  label: Text(
                    '${preset.$2}: ${preset.$1}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: isSel
                      ? primaryColor.withValues(alpha: 0.18)
                      : (isDark
                            ? const Color(0xFF1E222B)
                            : Colors.grey.shade100),
                  side: BorderSide(
                    color: isSel
                        ? primaryColor
                        : (isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade300),
                  ),
                  onPressed: () => _selectGraphPreset(preset.$1),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),

        // 3. Status Bar & Graph View Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF12141A) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Key points summary
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      rootsCount > 0 || vertexCount > 0 || yIntCount > 0
                          ? '$rootsCount root${rootsCount == 1 ? '' : 's'} • $vertexCount extrema • $yIntCount y-int'
                          : 'Range: x ∈ [${_graphPlot.xMin.toStringAsFixed(1)}, ${_graphPlot.xMax.toStringAsFixed(1)}]',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              // Zoom In (+)
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 18),
                tooltip: 'Zoom In Graph',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _graphPlot = _graphPlot.zoom(0.75);
                  });
                },
              ),

              // Zoom Out (-)
              IconButton(
                icon: const Icon(Icons.remove_rounded, size: 18),
                tooltip: 'Zoom Out Graph',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _graphPlot = _graphPlot.zoom(1.33);
                  });
                },
              ),

              // Reset Origin
              IconButton(
                icon: const Icon(Icons.filter_center_focus_rounded, size: 18),
                tooltip: 'Reset Origin (0,0)',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _graphPlot = _graphPlot.resetView();
                  });
                },
              ),

              // Toggle Key Points
              IconButton(
                icon: Icon(
                  Icons.radar_rounded,
                  size: 18,
                  color: _graphPlot.showKeyPoints ? primaryColor : Colors.grey,
                ),
                tooltip: 'Toggle Intercepts & Vertex',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _graphPlot = _graphPlot.copyWith(
                      showKeyPoints: !_graphPlot.showKeyPoints,
                    );
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 4. Interactive Live Preview
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (_) {
                      _graphLastScale = 1.0;
                    },
                    onScaleUpdate: (details) {
                      final xSpan = _graphPlot.xMax - _graphPlot.xMin;
                      final ySpan = _graphPlot.yMax - _graphPlot.yMin;

                      // Pinch zoom
                      if ((details.scale - _graphLastScale).abs() > 0.02) {
                        final factor = _graphLastScale / details.scale;
                        _graphLastScale = details.scale;
                        setState(() {
                          _graphPlot = _graphPlot.zoom(factor);
                        });
                        return;
                      }

                      // Pan
                      if (details.focalPointDelta != Offset.zero) {
                        final dxMath =
                            -(details.focalPointDelta.dx / 400.0) * xSpan;
                        final dyMath =
                            (details.focalPointDelta.dy / 250.0) * ySpan;
                        setState(() {
                          _graphPlot = _graphPlot.pan(dxMath, dyMath);
                        });
                      }
                    },
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: PlotPainter(
                        plot: _graphPlot,
                        compiledFunction: _graphFunction,
                        isDark: isDark,
                      ),
                    ),
                  ),

                  // Hint badge
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black54 : Colors.white70,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      child: Text(
                        'Pinch or use +/- to zoom • Drag to pan',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 5. Action Row
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reset View'),
              onPressed: () {
                setState(() {
                  _graphPlot = _graphPlot.resetView();
                });
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.show_chart_rounded, size: 20),
                label: const Text(
                  'Insert Graph to Whiteboard',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  final newPlot = _graphPlot.copyWith(
                    id: const Uuid().v4(),
                    rect: const Rect.fromLTWH(80, 160, 420, 360),
                  );
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .addPlot(newPlot);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Placed "${newPlot.equation}" graph on whiteboard!',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
