import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/ai_config.dart';
import '../state/whiteboard_notifier.dart';

class AiRecognitionSettingsDialog extends ConsumerWidget {
  const AiRecognitionSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const AiRecognitionSettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whiteboardControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF059669),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Recognition & AI',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Whiteboard automation preferences',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Developer override only: release builds use the Chalkmind
              // server and never show key settings.
              if (AiConfig.allowDeveloperKey) ...[
                const _AiProviderSection(),
                const Divider(height: 24),
              ],

              // 1. Auto Shape Detection Switch
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.interests_outlined,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Auto Shape Detection',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Convert hand-drawn strokes into perfect circles, triangles, rectangles, arrows, and lines.',
                  style: TextStyle(fontSize: 12),
                ),
                value: state.isAutoShapeEnabled,
                onChanged: (val) {
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .setAutoShape(val);
                },
              ),

              const Divider(height: 20),

              // 2. Auto Math Solver Switch
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calculate_outlined,
                    color: Color(0xFF059669),
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Auto Math Solver',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Automatically detect and solve equations or identities when writing "=".',
                  style: TextStyle(fontSize: 12),
                ),
                value: state.isAutoMathEnabled,
                onChanged: (val) {
                  ref
                      .read(whiteboardControllerProvider.notifier)
                      .setAutoMath(val);
                },
              ),

              const SizedBox(height: 16),

              // 3. Selective Solving Guide Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.highlight_alt_rounded,
                      size: 20,
                      color: Color(0xFF3B82F6),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Manual / Selector Mode',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.isAutoMathEnabled
                                ? 'Auto Math is currently ACTIVE. To prevent automatic solving while you write, turn off "Auto Math Solver" above. You can then use the Selector tool to solve specific formulas on demand.'
                                : 'Auto Math is OFF. Use the Selector tool on the toolbar to select any formula, geometry problem, or algebra, and tap "Solve Selected" to calculate on demand.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF1E3A8A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 4. Step-by-Step Info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E222B)
                      : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF374151)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 18,
                      color: Color(0xFF059669),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Whenever an equation is solved, click the "Steps" button in the suggestion bar to view complete pedagogical reasoning and insert the steps directly onto your whiteboard.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// API key + model configuration for every AI feature (vision math solver,
/// assistant, diagram generation). The key is stored on this device only.
class _AiProviderSection extends ConsumerStatefulWidget {
  const _AiProviderSection();

  @override
  ConsumerState<_AiProviderSection> createState() => _AiProviderSectionState();
}

class _AiProviderSectionState extends ConsumerState<_AiProviderSection> {
  late final TextEditingController _key;
  late final TextEditingController _model;
  bool _obscure = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final c = ref.read(aiConfigProvider);
    _key = TextEditingController(text: c.userApiKey);
    _model = TextEditingController(text: c.model);
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(aiConfigProvider.notifier)
        .update(apiKey: _key.text, model: _model.text);
    if (mounted) setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(aiConfigProvider);
    final status = config.usesDeveloperKey
        ? 'Direct (developer key)'
        : 'Using Chalkmind server';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              config.isConfigured
                  ? Icons.check_circle_rounded
                  : Icons.key_off_rounded,
              size: 18,
              color: config.isConfigured
                  ? const Color(0xFF059669)
                  : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(
              'Developer AI key (debug builds)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              status,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _key,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() => _saved = false),
          decoration: InputDecoration(
            isDense: true,
            labelText: 'API key',
            hintText: 'sk-or-...',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show key' : 'Hide key',
              icon: Icon(
                _obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 18,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _model,
          autocorrect: false,
          onChanged: (_) => setState(() => _saved = false),
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Model (must support images for handwriting & photos)',
            hintText: AiConfig.defaultModel,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Debug builds only. Leave empty to use the Chalkmind server (sign-in and plan limits apply).',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            TextButton.icon(
              onPressed: _save,
              icon: Icon(
                _saved ? Icons.check_rounded : Icons.save_rounded,
                size: 16,
              ),
              label: Text(_saved ? 'Saved' : 'Save'),
            ),
          ],
        ),
      ],
    );
  }
}
