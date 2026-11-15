import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/openrouter_client.dart';
import 'board_context.dart';
import 'diagram_builder.dart';

/// Teaching/learning actions offered by the assistant. Each reuses the same
/// client, board context and output pipeline.
enum AssistantAction {
  ask(
    'Ask',
    Icons.chat_bubble_outline_rounded,
    needsInput: true,
    usesBoard: true,
  ),
  explain('Explain', Icons.lightbulb_outline_rounded, usesBoard: true),
  check('Check my work', Icons.fact_check_outlined, usesBoard: true),
  hint('Give a hint', Icons.tips_and_updates_outlined, usesBoard: true),
  summarize('Summarize', Icons.summarize_outlined, usesBoard: true),
  practice('Practice questions', Icons.fitness_center_rounded, usesBoard: true),
  quiz('Quiz', Icons.quiz_outlined, usesBoard: true),
  flashcards('Flashcards', Icons.style_outlined, usesBoard: true),
  revisionNotes(
    'Revision notes',
    Icons.sticky_note_2_outlined,
    usesBoard: true,
  ),
  lessonPlan('Lesson plan', Icons.event_note_outlined, needsInput: true),
  worksheet('Worksheet', Icons.assignment_outlined, needsInput: true),
  flowchart(
    'Flowchart',
    Icons.account_tree_outlined,
    needsInput: true,
    isDiagram: true,
  ),
  mindMap('Mind map', Icons.hub_outlined, needsInput: true, isDiagram: true),
  conceptMap(
    'Concept map',
    Icons.bubble_chart_outlined,
    needsInput: true,
    isDiagram: true,
  );

  final String label;
  final IconData icon;
  final bool needsInput; // requires the text box (topic or question)
  final bool usesBoard; // sends board content as context
  final bool isDiagram; // produces editable diagram elements, not text

  const AssistantAction(
    this.label,
    this.icon, {
    this.needsInput = false,
    this.usesBoard = false,
    this.isDiagram = false,
  });

  DiagramKind get diagramKind => switch (this) {
    AssistantAction.flowchart => DiagramKind.flowchart,
    AssistantAction.mindMap => DiagramKind.mindmap,
    _ => DiagramKind.concept,
  };

  String get inputHint => switch (this) {
    AssistantAction.ask => 'Ask about the board, e.g. "Why is step 3 true?"',
    AssistantAction.lessonPlan =>
      'Topic and level, e.g. "Photosynthesis, grade 7, 45 min"',
    AssistantAction.worksheet =>
      'Topic and level, e.g. "Linear equations, grade 8"',
    AssistantAction.flowchart => 'Process, e.g. "How a bill becomes law"',
    AssistantAction.mindMap => 'Central topic, e.g. "Causes of World War I"',
    AssistantAction.conceptMap => 'Topic, e.g. "The water cycle"',
    _ => 'Optional: add focus or level (e.g. "grade 6")',
  };

  int get maxTokens => switch (this) {
    AssistantAction.hint => 250,
    AssistantAction.explain ||
    AssistantAction.ask ||
    AssistantAction.check => 900,
    AssistantAction.lessonPlan || AssistantAction.worksheet => 1600,
    _ => 1100,
  };
}

class AssistantTurn {
  final bool isUser;
  final String text;
  const AssistantTurn(this.isUser, this.text);
}

/// Board-aware AI assistant for teachers and students.
class BoardAssistant {
  static const String systemPrompt =
      'You are Chalkmind Tutor, an AI teaching assistant inside a digital classroom whiteboard used by teachers and students. '
      'Be accurate, clear and encouraging. Match the level of the material on the board. '
      'Output is shown as plain text on a whiteboard: do NOT use Markdown (no #, **, tables) or LaTeX. '
      'Write math with Unicode (x², √, π, ≤, ×, ÷, ½) and number steps as "1.", "2.". '
      'Keep answers focused; short paragraphs and short lines. '
      'Only describe what is actually on the board; if handwriting is unclear, say what you read and ask to confirm. '
      'If you are not sure an answer is correct, say so.';

  static String instructionFor(AssistantAction action, String input) {
    final extra = input.trim().isEmpty ? '' : '\nUser note: ${input.trim()}';
    switch (action) {
      case AssistantAction.ask:
        return 'Answer the user\'s question using the board as context.\nQuestion: ${input.trim()}';
      case AssistantAction.explain:
        return 'Explain the content shown, step by step, as a patient teacher would. Start with what it shows, then why it works, then one short worked example if useful.$extra';
      case AssistantAction.check:
        return 'This is a student\'s work. Check it carefully line by line. If everything is correct, say so and briefly confirm why. '
            'If there is a mistake, identify the FIRST incorrect step, quote it, explain what went wrong, and show the corrected step. '
            'Then show how the rest follows. Be specific and kind.$extra';
      case AssistantAction.hint:
        return 'Give ONE short hint (max 2 sentences) toward the next step of the problem on the board. Do not reveal the final answer.$extra';
      case AssistantAction.summarize:
        return 'Summarize this lesson content as 4-7 concise bullet points (use "•") covering the key ideas, then one line "Key takeaway: ...".$extra';
      case AssistantAction.practice:
        return 'Create 5 practice questions similar to the content on the board, gradually increasing in difficulty. '
            'Number them. After all questions, add a line "Answers:" followed by brief answers.$extra';
      case AssistantAction.quiz:
        return 'Create a 5-question multiple-choice quiz on this content. Each question has options A-D with one correct answer. '
            'After all questions add "Answer key:" with the letter and a one-line reason for each.$extra';
      case AssistantAction.flashcards:
        return 'Create 8 flashcards from this content in the format "Q: ...\\nA: ..." separated by blank lines. Keep each side short.$extra';
      case AssistantAction.revisionNotes:
        return 'Write concise revision notes for this content: key definitions, formulas or facts, a common mistake to avoid, and a 3-question self-check.$extra';
      case AssistantAction.lessonPlan:
        return 'Write a lesson plan for: ${input.trim()}\nInclude: learning objectives, prerequisite knowledge, timed sections (hook, explanation, guided practice, independent practice, exit ticket), '
            'what to draw on the whiteboard in each section, and common misconceptions.';
      case AssistantAction.worksheet:
        return 'Create a printable worksheet for: ${input.trim()}\nInclude a title, short instructions, 8 questions in 3 sections (warm-up, core, challenge), and an answer key at the end.';
      case AssistantAction.flowchart:
      case AssistantAction.mindMap:
      case AssistantAction.conceptMap:
        final kind = action == AssistantAction.flowchart
            ? 'a flowchart (sequential steps with decisions where relevant)'
            : action == AssistantAction.mindMap
            ? 'a mind map (one central topic with branches and sub-branches)'
            : 'a concept map (concepts linked by labelled relationships such as "causes", "is part of")';
        return 'Design $kind for: ${input.trim()}\n${DiagramSpec.schemaPrompt}';
    }
  }

  final AiConfig config;
  const BoardAssistant(this.config);

  /// Builds the chat messages: system prompt, a few prior turns for
  /// follow-up questions, then the new request with board context/image.
  List<Map<String, dynamic>> buildMessages({
    required AssistantAction action,
    required String input,
    BoardContext? board,
    String? uploadedImageBase64,
    List<AssistantTurn> history = const [],
  }) {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    // Last 4 turns only, text-only, to keep token use bounded.
    final recent = history.length > 4
        ? history.sublist(history.length - 4)
        : history;
    for (final t in recent) {
      final text = t.text.length > 1500
          ? '${t.text.substring(0, 1500)}…'
          : t.text;
      messages.add({'role': t.isUser ? 'user' : 'assistant', 'content': text});
    }

    final b = StringBuffer(instructionFor(action, input));
    if (board != null && action.usesBoard) {
      b.writeln('\n\n${board.description}');
    }
    if (uploadedImageBase64 != null) {
      b.writeln(
        '\nThe attached image was uploaded by the user (e.g. a textbook question or diagram). '
        'Read it carefully, transcribe any question you use, then respond.',
      );
    }
    final image =
        uploadedImageBase64 ?? ((action.usesBoard) ? board?.imageBase64 : null);
    messages.add(aiUserMessage(b.toString(), base64Png: image));
    return messages;
  }

  Stream<String> streamResponse({
    required AssistantAction action,
    required String input,
    BoardContext? board,
    String? uploadedImageBase64,
    List<AssistantTurn> history = const [],
    AiCancelToken? cancelToken,
  }) {
    return OpenRouterClient(config).stream(
      messages: buildMessages(
        action: action,
        input: input,
        board: board,
        uploadedImageBase64: uploadedImageBase64,
        history: history,
      ),
      temperature: action == AssistantAction.check ? 0.1 : 0.4,
      maxTokens: action.maxTokens,
      cancelToken: cancelToken,
    );
  }

  Future<DiagramSpec> generateDiagram({
    required AssistantAction action,
    required String topic,
    AiCancelToken? cancelToken,
  }) async {
    final content = await OpenRouterClient(config).complete(
      messages: buildMessages(action: action, input: topic),
      temperature: 0.2,
      maxTokens: 1400,
      cancelToken: cancelToken,
    );
    try {
      return DiagramSpec.parse(content, action.diagramKind);
    } on FormatException catch (e) {
      throw AiException(
        AiErrorKind.badResponse,
        'Diagram JSON invalid: ${e.message}',
      );
    }
  }

  /// Strips Markdown the model may still emit, for clean board text.
  static String toBoardText(String text) {
    var t = text.replaceAll('\r', '');
    t = t.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    t = t.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1]!);
    t = t.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m[1]!);
    t = t.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
    t = t.replaceAll('```', '');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }
}

/// Validates and normalises an uploaded image for AI analysis.
class UploadedImage {
  static const int maxBytes = 10 * 1024 * 1024;
  static const int maxSide = 1600;

  /// Checks size and file signature (not just the extension), decodes it to
  /// prove it is a real image, downsizes it, and re-encodes as PNG.
  /// Throws [FormatException] with a user-facing message if rejected.
  static Future<String> prepare(Uint8List bytes) async {
    if (bytes.isEmpty) throw const FormatException('The file is empty.');
    if (bytes.length > maxBytes) {
      throw const FormatException('Image is larger than 10 MB.');
    }
    if (!_hasImageSignature(bytes)) {
      throw const FormatException(
        'Unsupported file. Use a PNG, JPEG, WebP or GIF image.',
      );
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      final scale = (w > h ? maxSide / w : maxSide / h).clamp(0.0, 1.0);
      codec = await descriptor.instantiateCodec(
        targetWidth: (w * scale).round().clamp(1, maxSide),
        targetHeight: (h * scale).round().clamp(1, maxSide),
      );
      image = (await codec.getNextFrame()).image;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw const FormatException('Could not read the image.');
      return base64Encode(png.buffer.asUint8List());
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Could not read the image. It may be corrupted.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static bool _hasImageSignature(Uint8List b) {
    bool starts(List<int> sig, [int offset = 0]) {
      if (b.length < offset + sig.length) return false;
      for (int i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    return starts([0x89, 0x50, 0x4E, 0x47]) || // PNG
        starts([0xFF, 0xD8, 0xFF]) || // JPEG
        starts([0x47, 0x49, 0x46, 0x38]) || // GIF
        (starts([0x52, 0x49, 0x46, 0x46]) &&
            starts([0x57, 0x45, 0x42, 0x50], 8)); // WebP
  }
}
