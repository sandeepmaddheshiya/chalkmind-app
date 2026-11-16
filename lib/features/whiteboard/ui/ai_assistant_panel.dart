import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/openrouter_client.dart';
import '../../../core/backend/backend.dart';
import '../../../core/backend/account.dart';
import '../../account/account_sheets.dart';
import '../../account/account_style.dart';
import '../assistant/board_assistant.dart';
import '../assistant/board_context.dart';
import '../assistant/diagram_builder.dart';
import '../models/text_model.dart';
import '../state/whiteboard_notifier.dart';

class _Message {
  final bool isUser;
  final AssistantAction action;
  String text;
  String? error;
  bool streaming;
  bool hadImage;
  String? note; // e.g. diagram inserted

  _Message({
    required this.isUser,
    required this.action,
    this.text = '',
    this.streaming = false,
    this.hadImage = false,
  });
}

/// Side panel for the board-aware AI assistant. Non-modal: the canvas stays
/// fully interactive while responses stream in.
class AiAssistantPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const AiAssistantPanel({super.key, required this.onClose});

  @override
  ConsumerState<AiAssistantPanel> createState() => _AiAssistantPanelState();
}

class _AiAssistantPanelState extends ConsumerState<AiAssistantPanel> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  AssistantAction _mode = AssistantAction.ask;
  AiCancelToken? _cancel;
  StreamSubscription<String>? _sub;
  String? _attachedImage; // base64 PNG
  String? _attachedName;
  bool get _busy => _cancel != null;

  @override
  void dispose() {
    _cancel?.cancel();
    _sub?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _stop() {
    _cancel?.cancel();
    _sub?.cancel();
    setState(() {
      for (final m in _messages) {
        if (m.streaming) {
          m.streaming = false;
          if (m.text.isEmpty) m.error = 'Stopped.';
        }
      }
      _cancel = null;
    });
  }

  Future<void> _pickImage() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      final f = files.first;
      final len = f.lengthSync() ?? await f.length() ?? 0;
      if (len > UploadedImage.maxBytes) {
        throw const FormatException('Image is larger than 10 MB.');
      }
      final b64 = await UploadedImage.prepare(await f.readAsBytes());
      if (!mounted) return;
      setState(() {
        _attachedImage = b64;
        _attachedName = f.name;
        if (_mode.isDiagram ||
            _mode == AssistantAction.lessonPlan ||
            _mode == AssistantAction.worksheet) {
          _mode = AssistantAction.explain;
        }
      });
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not open the image: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onActionTap(AssistantAction a) {
    if (_busy) return;
    setState(() => _mode = a);
    if (a.needsInput && _input.text.trim().isEmpty) {
      _inputFocus.requestFocus();
      return;
    }
    _run(a);
  }

  /// Visible board area origin in canvas coordinates, for inserting content
  /// where the user is currently looking.
  Offset _insertOrigin() {
    final s = ref.read(whiteboardControllerProvider);
    final z = s.zoomScale <= 0 ? 1.0 : s.zoomScale;
    return Offset(-s.panOffset.dx / z + 60 / z, -s.panOffset.dy / z + 80 / z);
  }

  Future<void> _run(AssistantAction action) async {
    final config = ref.read(aiConfigProvider);
    final input = _input.text.trim();
    if (action.needsInput && input.isEmpty) {
      _inputFocus.requestFocus();
      return;
    }
    final image = _attachedImage;
    final history = [
      for (final m in _messages)
        if (m.error == null && m.text.isNotEmpty && !m.action.isDiagram)
          AssistantTurn(m.isUser, m.text),
    ];

    final userLabel = input.isEmpty ? action.label : '${action.label}: $input';
    final reply = _Message(isUser: false, action: action, streaming: true);
    setState(() {
      _messages.add(
        _Message(
          isUser: true,
          action: action,
          text: userLabel,
          hadImage: image != null,
        ),
      );
      _messages.add(reply);
      _input.clear();
      _attachedImage = null;
      _attachedName = null;
    });
    _scrollToEnd();

    if (!config.isConfigured) {
      AiBackend.requestGate(AiGateReason.signInRequired);
      setState(() {
        reply.streaming = false;
        reply.error = const AiException(
          AiErrorKind.notConfigured,
          '',
        ).userMessage;
      });
      return;
    }

    final token = _cancel = AiCancelToken();
    final assistant = BoardAssistant(config);

    try {
      if (action.isDiagram) {
        final spec = await assistant.generateDiagram(
          action: action,
          topic: input,
          cancelToken: token,
        );
        if (!mounted || token.isCancelled) return;
        final elements = DiagramBuilder.build(spec, origin: _insertOrigin());
        ref
            .read(whiteboardControllerProvider.notifier)
            .insertElements(
              shapes: elements.shapes,
              texts: elements.texts,
              description: 'Insert ${action.label}',
            );
        setState(() {
          reply.streaming = false;
          reply.text = spec.title.isEmpty ? action.label : spec.title;
          reply.note =
              'Inserted ${spec.nodes.length} editable nodes and ${spec.edges.length} links. '
              'It is selected: drag to move, or Ctrl+Z to undo.';
        });
        return;
      }

      BoardContext? board;
      if (action.usesBoard && image == null) {
        final s = ref.read(whiteboardControllerProvider);
        board = await BoardContext.build(
          page: s.project.currentPage,
          pageNumber: s.project.currentPageIndex + 1,
          totalPages: s.project.totalPages,
          selectedIds: s.selectedObjectIds,
        );
        if (board.isEmpty && action != AssistantAction.ask) {
          setState(() {
            reply.streaming = false;
            reply.error =
                'The board is empty. Write or select something first, or attach an image.';
          });
          _cancel = null;
          return;
        }
      }
      if (token.isCancelled) return;

      final completer = Completer<void>();
      _sub = assistant
          .streamResponse(
            action: action,
            input: input,
            board: board,
            uploadedImageBase64: image,
            history: history,
            cancelToken: token,
          )
          .listen(
            (delta) {
              if (!mounted) return;
              setState(() => reply.text += delta);
              _scrollToEnd();
            },
            onError: (Object e) {
              if (mounted) {
                setState(
                  () => reply.error = e is AiException
                      ? e.userMessage
                      : 'Something went wrong: $e',
                );
              }
              if (!completer.isCompleted) completer.complete();
            },
            onDone: () {
              if (!completer.isCompleted) completer.complete();
            },
            cancelOnError: true,
          );
      await completer.future;
    } on AiException catch (e) {
      if (mounted && e.kind != AiErrorKind.cancelled) {
        setState(() => reply.error = e.userMessage);
      }
    } catch (e) {
      if (mounted) setState(() => reply.error = 'Something went wrong: $e');
    } finally {
      if (mounted) {
        setState(() {
          reply.streaming = false;
          if (identical(_cancel, token)) _cancel = null;
        });
      }
    }
  }

  void _insertOnBoard(_Message m) {
    final text = BoardAssistant.toBoardText(m.text);
    if (text.isEmpty) return;
    final s = ref.read(whiteboardControllerProvider);
    ref
        .read(whiteboardControllerProvider.notifier)
        .insertElements(
          texts: [
            TextObject(
              id: const Uuid().v4(),
              text: text,
              position: _insertOrigin(),
              fontSize: 18,
              colorValue: s.project.currentPage.background.isDark
                  ? 0xFFF9FAFB
                  : 0xFF111827,
            ),
          ],
          description: 'Insert AI ${m.action.label}',
        );
    _snack('Added to the board (selected, drag to place).');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final config = ref.watch(aiConfigProvider);
    final selectionCount = ref.watch(
      whiteboardControllerProvider.select((s) => s.selectedObjectIds.length),
    );

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(18),
      color: isDark ? const Color(0xFF161A22) : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.psychology_alt_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI Assistant',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Tooltip(
                  message: 'What the AI will look at for board actions',
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      selectionCount > 0
                          ? Icons.highlight_alt_rounded
                          : Icons.crop_free_rounded,
                      size: 14,
                    ),
                    label: Text(
                      selectionCount > 0
                          ? 'Selection ($selectionCount)'
                          : 'Whole page',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          _AccountBanner(config: config),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in AssistantAction.values)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(a.icon, size: 15),
                    label: Text(
                      a.label,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    selected: _mode == a,
                    onSelected: _busy ? null : (_) => _onActionTap(a),
                    tooltip: a.needsInput
                        ? '${a.label} (type a topic below)'
                        : '${a.label} using the ${selectionCount > 0 ? 'selection' : 'page'}',
                  ),
              ],
            ),
          ),

          // Conversation
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Select part of the board (or use the whole page), then pick an action.\n\n'
                        'Students: Explain, Hint, Check my work, Practice.\n'
                        'Teachers: Quiz, Worksheet, Lesson plan, Flowchart, Mind map.\n\n'
                        'Attach a photo of a textbook question to have it explained.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.hintColor,
                          height: 1.45,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) =>
                        _buildMessage(_messages[i], theme, isDark),
                  ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_attachedName != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.image_outlined, size: 16),
                      label: Text(
                        _attachedName!,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: () => setState(() {
                        _attachedImage = null;
                        _attachedName = null;
                      }),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Attach an image (textbook question, diagram)',
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      onPressed: _busy ? null : _pickImage,
                    ),
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter): () {
                            if (!_busy) _run(_mode);
                          },
                        },
                        child: TextField(
                          controller: _input,
                          focusNode: _inputFocus,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (!_busy) _run(_mode);
                          },
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: _mode.inputHint,
                            hintStyle: const TextStyle(fontSize: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _busy
                        ? IconButton.filledTonal(
                            tooltip: 'Stop',
                            icon: const Icon(Icons.stop_rounded),
                            onPressed: _stop,
                          )
                        : IconButton.filled(
                            tooltip: _mode.label,
                            icon: Icon(
                              _mode.isDiagram
                                  ? Icons.account_tree_rounded
                                  : Icons.send_rounded,
                            ),
                            onPressed: () => _run(_mode),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(_Message m, ThemeData theme, bool isDark) {
    if (m.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.hadImage)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.image_outlined, size: 14),
                ),
              Flexible(
                child: Text(m.text, style: const TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E232D) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.text.isEmpty && m.streaming && m.error == null)
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  m.action.isDiagram ? 'Designing diagram…' : 'Thinking…',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ],
            ),
          if (m.text.isNotEmpty)
            SelectableText(
              m.text,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          if (m.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                m.note!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          if (m.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m.error!,
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          if (!m.streaming && m.text.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Report answer',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.flag_outlined,
                    size: 16,
                    color: theme.hintColor,
                  ),
                  onPressed: () => _report(m),
                ),
                if (!m.action.isDiagram) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy', style: TextStyle(fontSize: 11.5)),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: BoardAssistant.toBoardText(m.text)),
                      );
                      _snack('Copied');
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add_box_outlined, size: 14),
                    label: const Text(
                      'Insert on board',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    onPressed: () => _insertOnBoard(m),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  void _report(_Message m) {
    final i = _messages.indexOf(m);
    final prompt = i > 0 && _messages[i - 1].isUser
        ? _messages[i - 1].text
        : null;
    reportAiAnswer(
      context,
      action: 'assistant_${m.action.name}',
      answer: m.text,
      prompt: prompt,
    );
  }
}

/// Sign-in prompt (signed out) or remaining free answers (signed in).
class _AccountBanner extends ConsumerWidget {
  final AiConfig config;
  const _AccountBanner({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    if (config.usesDeveloperKey) return const SizedBox.shrink();
    final me = account.me;
    if (me == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          gradient: AccountColors.headerGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: AccountColors.yellow,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Sign in with Google to use AI. It\'s free.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AccountColors.chalk,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AccountColors.yellow,
                foregroundColor: AccountColors.onYellow,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () => showSignInSheet(context),
              child: const Text(
                'Sign in',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }
    if (me.plan.isPlus || me.quota.limit == 0) return const SizedBox.shrink();
    final left = me.quota.remaining;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Icon(
            Icons.bolt_rounded,
            size: 16,
            color: left == 0
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              left == 0
                  ? "No free AI answers left today"
                  : '$left free AI answer${left == 1 ? '' : 's'} left today',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => showPaywall(context, limitReached: left == 0),
            child: const Text('Get Plus'),
          ),
        ],
      ),
    );
  }
}
