import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/openrouter_client.dart';
import '../assistant/board_assistant.dart';
import '../models/text_model.dart';
import '../pdf/pdf_text_index.dart';
import '../pdf/text_lookup_service.dart';
import '../state/whiteboard_notifier.dart';

/// After highlighting text on an imported PDF page, offers "Meaning" and
/// "Explain"; streams the answer and can add it to the board as a note.
class PdfLookupOverlay extends ConsumerStatefulWidget {
  const PdfLookupOverlay({super.key});

  @override
  ConsumerState<PdfLookupOverlay> createState() => _PdfLookupOverlayState();
}

class _PdfLookupOverlayState extends ConsumerState<PdfLookupOverlay> {
  HighlightedText? _for; // lookup the current answer belongs to
  LookupAction? _action;
  String _answer = '';
  String? _error;
  bool _busy = false;
  AiCancelToken? _cancel;
  StreamSubscription<String>? _sub;

  @override
  void dispose() {
    _cancel?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _reset() {
    _cancel?.cancel();
    _sub?.cancel();
    _cancel = null;
    _action = null;
    _answer = '';
    _error = null;
    _busy = false;
  }

  Future<void> _run(HighlightedText h, LookupAction action) async {
    _reset();
    final config = ref.read(aiConfigProvider);
    setState(() {
      _for = h;
      _action = action;
      _busy = true;
    });
    if (!config.isConfigured) {
      setState(() {
        _busy = false;
        _error = const AiException(AiErrorKind.notConfigured, '').userMessage;
      });
      return;
    }
    final token = _cancel = AiCancelToken();
    _sub = TextLookupService.stream(config, action, h, cancelToken: token)
        .listen(
          (d) {
            if (mounted && identical(_cancel, token)) {
              setState(() => _answer += d);
            }
          },
          onError: (Object e) {
            if (!mounted || !identical(_cancel, token)) return;
            setState(() {
              _busy = false;
              _error = e is AiException
                  ? e.userMessage
                  : 'Could not look this up: $e';
            });
          },
          onDone: () {
            if (mounted && identical(_cancel, token)) {
              setState(() => _busy = false);
            }
          },
          cancelOnError: true,
        );
  }

  /// Wraps text so a board note doesn't run off as one very long line.
  static String _wrap(String text, {int width = 48}) {
    final out = <String>[];
    for (final para in text.split('\n')) {
      var line = '';
      for (final word in para.split(' ')) {
        if (line.isNotEmpty && line.length + 1 + word.length > width) {
          out.add(line);
          line = word;
        } else {
          line = line.isEmpty ? word : '$line $word';
        }
      }
      out.add(line);
    }
    return out.join('\n').trim();
  }

  void _addAsNote(HighlightedText h) {
    final body = BoardAssistant.toBoardText(_answer);
    if (body.isEmpty) return;
    final note = TextObject(
      id: const Uuid().v4(),
      text: _wrap(body),
      // Just below the highlighted line, so it reads as an annotation.
      position: h.boardRect.bottomLeft + const Offset(0, 6),
      fontSize: 14,
      colorValue: 0xFF1D4ED8,
    );
    ref
        .read(whiteboardControllerProvider.notifier)
        .insertElements(
          texts: [note],
          description: 'Add ${_action?.label ?? 'look-up'} note',
          select: false,
        );
    _close();
  }

  void _close() {
    _reset();
    ref.read(whiteboardControllerProvider.notifier).dismissPdfLookup();
  }

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(
      whiteboardControllerProvider.select((s) => s.pdfLookup),
    );
    if (h == null) return const SizedBox.shrink();
    if (!identical(h, _for) && _action != null) {
      // A new highlight replaced the previous one.
      _reset();
      _for = null;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final label = h.hasText
        ? '“${h.text.length > 42 ? '${h.text.substring(0, 40)}…' : h.text}”'
        : 'Highlighted area';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(18),
          color: isDark ? const Color(0xFF1E222B) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.menu_book_rounded,
                      size: 18,
                      color: Color(0xFFCA8A04),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final a in LookupAction.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: _action == a
                            ? FilledButton.tonal(
                                onPressed: _busy ? null : () => _run(h, a),
                                child: Text(a.label),
                              )
                            : TextButton(
                                onPressed: () => _run(h, a),
                                child: Text(a.label),
                              ),
                      ),
                    IconButton(
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: _close,
                    ),
                  ],
                ),
                if (_action != null) ...[
                  const Divider(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 4),
                        child: _error != null
                            ? Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              )
                            : _answer.isEmpty
                            ? Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Looking it up…',
                                    style: TextStyle(
                                      color: theme.hintColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              )
                            : SelectableText(
                                _answer,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                      ),
                    ),
                  ),
                  if (!_busy && _answer.isNotEmpty && _error == null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.copy_rounded, size: 15),
                          label: const Text('Copy'),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(
                              text: BoardAssistant.toBoardText(_answer),
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.note_add_outlined, size: 16),
                          label: const Text('Add as note'),
                          onPressed: () => _addAsNote(h),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
