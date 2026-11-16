import '../../../core/ai/ai_config.dart';
import '../../../core/ai/openrouter_client.dart';
import 'pdf_text_index.dart';

enum LookupAction {
  meaning('Meaning'),
  explain('Explain');

  final String label;
  const LookupAction(this.label);
}

/// Explains text a student or teacher highlighted on an imported PDF.
class TextLookupService {
  static const String systemPrompt =
      'You help students understand their reading material. Output plain text for a whiteboard: '
      'no Markdown, no LaTeX (use Unicode such as x², H₂O, →). Be accurate, simple and brief. '
      'Use the surrounding passage to pick the right sense of a word. If unsure, say so.';

  static String instruction(LookupAction action, HighlightedText h) {
    final passage = h.context.length > 1500
        ? h.context.substring(0, 1500)
        : h.context;
    final target = h.hasText
        ? 'Highlighted text: "${h.text}"\nSurrounding passage: "$passage"'
        : 'The highlighted part of the page is in the attached image (a scan). Read it first.';
    switch (action) {
      case LookupAction.meaning:
        return '$target\n\nGive the meaning of the highlighted word or phrase as it is used here. '
            'Format:\n<term> (<part of speech, if a single word>)\n<simple definition, 1-2 sentences>\n'
            'Example: <one short example sentence>\n'
            'If the highlight is a whole sentence or formula, say what it means in simple words instead.';
      case LookupAction.explain:
        return '$target\n\nExplain the highlighted text to a student in simple words (max 120 words): '
            'what it says, why it matters, and any key term or formula in it.';
    }
  }

  static Future<List<Map<String, dynamic>>> buildMessages(
    LookupAction action,
    HighlightedText h,
  ) async {
    String? image;
    if (!h.hasText) {
      image = await PdfTextIndex.cropRegionPng(h.pdf, h.boardRect);
    }
    return [
      {'role': 'system', 'content': systemPrompt},
      aiUserMessage(instruction(action, h), base64Png: image),
    ];
  }

  static Stream<String> stream(
    AiConfig config,
    LookupAction action,
    HighlightedText h, {
    AiCancelToken? cancelToken,
  }) async* {
    final messages = await buildMessages(action, h);
    yield* OpenRouterClient(config).stream(
      messages: messages,
      temperature: 0.2,
      maxTokens: action == LookupAction.meaning ? 250 : 450,
      cancelToken: cancelToken,
      action: 'lookup_${action.name}',
    );
  }
}
