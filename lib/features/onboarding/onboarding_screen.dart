import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'onboarding_prefs.dart';

class _OnboardingPage {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final List<(IconData, String)> points;
  final String? note;
  final bool useLogo; // show the app logo instead of the icon tile
  const _OnboardingPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.points,
    this.note,
    this.useLogo = false,
  });
}

const _pages = [
  _OnboardingPage(
    icon: Icons.gesture_rounded,
    color: Color(0xFF0F5A4D),
    useLogo: true,
    title: 'Welcome to Chalkmind',
    body:
        'A smart whiteboard for teaching lessons, solving problems and taking notes.',
    points: [
      (Icons.school_outlined, 'Teachers: explain, present and build lessons'),
      (Icons.edit_note_rounded, 'Students: solve, take notes and revise'),
      (Icons.save_outlined, 'Everything saves automatically on this device'),
    ],
  ),
  _OnboardingPage(
    icon: Icons.edit_rounded,
    color: Color(0xFF0F766E),
    title: 'Write naturally',
    body:
        'Pen, pencil, marker and highlighter feel like ink. Rest your palm while writing with a stylus.',
    points: [
      (Icons.pinch_outlined, 'Pinch to zoom, two fingers to move around'),
      (
        Icons.auto_fix_normal_rounded,
        'Eraser: tap it again to erase only part of a stroke',
      ),
      (Icons.highlight_alt_rounded, 'Select to move, copy or delete anything'),
    ],
  ),
  _OnboardingPage(
    icon: Icons.functions_rounded,
    color: Color(0xFF059669),
    title: 'Smart maths & shapes',
    body:
        'Write an equation ending in "=" and Chalkmind solves it, in your handwriting.',
    points: [
      (
        Icons.interests_outlined,
        'Rough circles, boxes and arrows snap into neat shapes',
      ),
      (Icons.show_chart_rounded, 'Plot graphs of equations right on the board'),
      (Icons.list_alt_rounded, 'See step-by-step working for any answer'),
    ],
  ),
  _OnboardingPage(
    icon: Icons.psychology_alt_rounded,
    color: Color(0xFFB45309),
    title: 'Your AI tutor',
    body: 'Select anything on the board and ask the AI Assistant.',
    points: [
      (
        Icons.lightbulb_outline_rounded,
        'Explain, give a hint, or check a student\'s working',
      ),
      (Icons.quiz_outlined, 'Make practice questions, quizzes and flashcards'),
      (
        Icons.account_tree_outlined,
        'Generate flowcharts and mind maps you can edit',
      ),
    ],
    note:
        'AI features send only what you choose (your selection, page or photo) to an AI '
        'service to get an answer. Nothing is sent unless you use an AI feature.',
  ),
  _OnboardingPage(
    icon: Icons.picture_as_pdf_rounded,
    color: Color(0xFFBE123C),
    title: 'Bring your PDFs',
    body:
        'Import worksheets, textbook chapters or notes and write right on top of them.',
    points: [
      (Icons.border_color_rounded, 'Highlight a word to see its meaning'),
      (
        Icons.menu_book_rounded,
        'Highlight a passage to get it explained simply',
      ),
      (Icons.ios_share_rounded, 'Export your annotated pages as PDF or images'),
    ],
  ),
];

/// First-launch welcome: what Chalkmind does, in five short pages.
class OnboardingScreen extends StatefulWidget {
  /// Called when the user finishes or skips (after the choice is saved).
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await OnboardingPrefs.markOnboardingDone();
    if (mounted) widget.onDone();
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    if (_index > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _pages[_index];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _back,
        const SingleActivator(LogicalKeyboardKey.escape): _finish,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Top bar: progress + skip
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Text(
                        '${_index + 1} of ${_pages.length}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                      const Spacer(),
                      if (!_isLast)
                        TextButton(
                          onPressed: _finish,
                          child: const Text('Skip'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _PageBody(page: _pages[i]),
                  ),
                ),
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? page.color : theme.dividerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Row(
                    children: [
                      if (_index > 0)
                        OutlinedButton(
                          onPressed: _back,
                          child: const Text('Back'),
                        )
                      else
                        const SizedBox.shrink(),
                      const Spacer(),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: page.color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                            ),
                            onPressed: _next,
                            icon: Icon(
                              _isLast
                                  ? Icons.check_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _isLast ? 'Get started' : 'Next',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  final _OnboardingPage page;
  const _PageBody({required this.page});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 720 && c.maxWidth > c.maxHeight;
        final art = _Illustration(
          icon: page.icon,
          color: page.color,
          useLogo: page.useLogo,
          size: wide ? 220 : (c.maxHeight < 560 ? 120 : 170),
        );
        final text = Column(
          crossAxisAlignment: wide
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              page.title,
              textAlign: wide ? TextAlign.start : TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              page.body,
              textAlign: wide ? TextAlign.start : TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.4,
                color: theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  for (final (icon, label) in page.points)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: page.color.withValues(
                                alpha: isDark ? 0.22 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(icon, size: 18, color: page.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (page.note != null) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1F2430)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        size: 18,
                        color: theme.hintColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          page.note!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 24),
            child: Center(
              child: wide
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        art,
                        const SizedBox(width: 48),
                        Flexible(child: text),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [art, const SizedBox(height: 24), text],
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Simple layered illustration: soft blobs behind a large icon tile.
class _Illustration extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool useLogo;
  const _Illustration({
    required this.icon,
    required this.color,
    required this.size,
    this.useLogo = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
            ),
          ),
          Positioned(
            right: size * 0.06,
            top: size * 0.10,
            child: Container(
              width: size * 0.22,
              height: size * 0.22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.18),
              ),
            ),
          ),
          if (useLogo)
            Container(
              width: size * 0.56,
              height: size * 0.56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.13),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/brand/chalkmind_logo.png',
                semanticLabel: 'Chalkmind logo',
              ),
            )
          else
            Container(
              width: size * 0.5,
              height: size * 0.5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(size * 0.14),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: size * 0.26),
            ),
        ],
      ),
    );
  }
}
