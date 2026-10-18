import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/whiteboard_notifier.dart';

class MathSuggestionOverlay extends ConsumerWidget {
  const MathSuggestionOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);
    final mathResult = state.handwritingMathResult;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (state.isCalculatingMath && mathResult == null) {
      return Center(
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(30),
          color: isDark ? const Color(0xFF1E222B) : Colors.white,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Calculating solution...',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (mathResult == null) return const SizedBox.shrink();
    if (mathResult.answer.isEmpty ||
        mathResult.answer.contains('{') ||
        mathResult.answer.contains('}') ||
        mathResult.answer.contains('expression') ||
        mathResult.expression.contains('{') ||
        mathResult.expression.contains('}') ||
        mathResult.expression.contains('expression')) {
      return const SizedBox.shrink();
    }

    final answerDisplay = mathResult.answer.length > 8
        ? 'Write Answer'
        : 'Write "${mathResult.answer}"';

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 32,
        ),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(30),
          color: isDark ? const Color(0xFF1E222B) : Colors.white,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
                width: 1.2,
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 10),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      children: [
                        TextSpan(
                          text: '${mathResult.expression} ',
                          style: const TextStyle(fontWeight: FontWeight.normal),
                        ),
                        TextSpan(
                          text: mathResult.answer,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Accept Button - Writes Answer in handwriting
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: const Icon(Icons.draw_rounded, size: 16),
                    label: Text(
                      answerDisplay,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      ref.read(whiteboardControllerProvider.notifier).acceptHandwrittenMath();
                    },
                  ),

                  const SizedBox(width: 8),

                  // Step-by-Step Explanation Button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : const Color(0xFF1E3A8A),
                      side: BorderSide(
                        color: isDark ? Colors.white24 : const Color(0xFF93C5FD),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: const Icon(Icons.auto_stories_outlined, size: 16),
                    label: const Text(
                      'Steps',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      _showStepByStepDialog(context, ref, mathResult);
                    },
                  ),

                  const SizedBox(width: 6),

                  // Dismiss Button
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Dismiss',
                    onPressed: () {
                      ref.read(whiteboardControllerProvider.notifier).dismissHandwrittenMath();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showStepByStepDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic mathResult,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<String> steps = mathResult.steps ?? <String>[];
    final String? explanation = mathResult.explanation;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.psychology_outlined,
                  color: Color(0xFF059669),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Step-by-Step Solution',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Problem & Answer Header Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF059669).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Given Equation / Problem:',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${mathResult.expression} ${mathResult.answer}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Step-by-Step Breakdown
                  if (steps.isNotEmpty) ...[
                    const Text(
                      'Solution Steps:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(top: 2, right: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E3A8A),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                steps[i],
                                style: const TextStyle(fontSize: 13, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ] else ...[
                    const Text(
                      'Direct Evaluation:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Expression: ${mathResult.expression}\nEvaluated exact mathematical result: ${mathResult.answer}',
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],

                  // Theoretical Explanation
                  if (explanation != null && explanation.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 18,
                            color: Color(0xFF3B82F6),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              explanation,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: isDark ? Colors.white70 : const Color(0xFF1E3A8A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            // Insert Steps on Canvas
            OutlinedButton.icon(
              icon: const Icon(Icons.add_to_photos_rounded, size: 16),
              label: const Text('Insert Steps on Board'),
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.read(whiteboardControllerProvider.notifier).insertMathSteps(mathResult);
              },
            ),

            // Write Answer on Canvas
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
              ),
              icon: const Icon(Icons.draw_rounded, size: 16),
              label: Text('Write "${mathResult.answer}"'),
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.read(whiteboardControllerProvider.notifier).acceptHandwrittenMath();
              },
            ),

            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
