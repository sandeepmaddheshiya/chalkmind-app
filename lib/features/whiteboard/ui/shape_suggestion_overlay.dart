import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tool_type.dart';
import '../state/whiteboard_notifier.dart';

class ShapeSuggestionOverlay extends ConsumerWidget {
  const ShapeSuggestionOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);
    final suggestion = state.shapeSuggestion;

    if (suggestion == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shapeName = suggestion.shapeType.displayName;

    IconData shapeIcon;
    switch (suggestion.shapeType) {
      case ShapeType.circle:
        shapeIcon = Icons.radio_button_unchecked_rounded;
        break;
      case ShapeType.rectangle:
        shapeIcon = Icons.crop_square_rounded;
        break;
      case ShapeType.triangle:
        shapeIcon = Icons.change_history_rounded;
        break;
      case ShapeType.line:
        shapeIcon = Icons.horizontal_rule_rounded;
        break;
      case ShapeType.arrow:
        shapeIcon = Icons.arrow_forward_rounded;
        break;
      case ShapeType.star:
        shapeIcon = Icons.star_outline_rounded;
        break;
      case ShapeType.diamond:
        shapeIcon = Icons.diamond_outlined;
        break;
      case ShapeType.pentagon:
        shapeIcon = Icons.pentagon_outlined;
        break;
      case ShapeType.hexagon:
        shapeIcon = Icons.hexagon_outlined;
        break;
      case ShapeType.heptagon:
      case ShapeType.octagon:
        shapeIcon = Icons.polyline_rounded;
        break;
    }

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
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  shapeIcon,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Convert to $shapeName?',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 14),

              // Accept Button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(0, 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Convert', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () {
                  ref.read(whiteboardControllerProvider.notifier).acceptShapeSuggestion();
                },
              ),

              const SizedBox(width: 8),

              // Dismiss / Keep Hand-Drawn Button
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Keep Hand-Drawn', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  ref.read(whiteboardControllerProvider.notifier).dismissShapeSuggestion();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
