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
                  'Write "${mathResult.answer}"',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  ref.read(whiteboardControllerProvider.notifier).acceptHandwrittenMath();
                },
              ),

              const SizedBox(width: 8),

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
    );
  }
}
