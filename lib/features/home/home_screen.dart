import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../whiteboard/models/background_style.dart';
import '../whiteboard/models/page_model.dart';
import '../whiteboard/models/project_model.dart';
import '../whiteboard/state/whiteboard_notifier.dart';
import '../onboarding/onboarding_screen.dart';
import '../whiteboard/pdf/pdf_import_flow.dart';
import '../whiteboard/ui/whiteboard_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<ProjectModel> _recentProjects = [];
  ProjectModel? _recoverableProject;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final storage = ref.read(projectStorageProvider);
    final recovery = ref.read(recoveryServiceProvider);

    final projects = await storage.listProjects();
    final hasDraft = await recovery.hasRecoverableSession();
    ProjectModel? draft;
    if (hasDraft) {
      draft = await recovery.loadRecoveryDraft();
    }

    if (mounted) {
      setState(() {
        _recentProjects = projects;
        _recoverableProject = draft;
        _isLoading = false;
      });
    }
  }

  void _openNewBoard({CanvasBackground? initialBackground}) {
    final newProject = ProjectModel.createEmpty();
    if (initialBackground != null) {
      final updatedPage = newProject.pages.first.copyWith(
        background: initialBackground,
      );
      final customizedProject = newProject.copyWith(pages: [updatedPage]);
      ref
          .read(whiteboardControllerProvider.notifier)
          .loadProject(customizedProject);
    } else {
      ref.read(whiteboardControllerProvider.notifier).loadProject(newProject);
    }

    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WhiteboardScreen()))
        .then((_) => _loadData());
  }

  /// Import a PDF as a new board (one board page per PDF page).
  Future<void> _importPdf() async {
    final result = await PdfImportFlow.pickAndImport(context);
    if (result == null || !mounted) return;
    final name = result.pages.first.pdf?.sourceName ?? 'PDF';
    final title = name.toLowerCase().endsWith('.pdf')
        ? name.substring(0, name.length - 4)
        : name;
    final project = ProjectModel.createEmpty(
      title: title,
    ).copyWith(pages: result.pages, currentPageIndex: 0);
    try {
      await ref.read(projectStorageProvider).saveProject(project);
    } catch (e) {
      debugPrint('Could not save imported board: $e');
    }
    if (!mounted) return;
    _openExistingBoard(project);
  }

  Future<void> _openExistingBoard(ProjectModel project) async {
    // The list holds lightweight summaries; load the full board to open it.
    if (project.isSummary) {
      final full = await ref
          .read(projectStorageProvider)
          .loadProject(project.id);
      if (!mounted) return;
      if (full == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This board could not be opened. It may have been deleted.',
            ),
          ),
        );
        await _loadData();
        return;
      }
      project = full;
    }
    if (!mounted) return;
    ref.read(whiteboardControllerProvider.notifier).loadProject(project);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WhiteboardScreen()))
        .then((_) => _loadData());
  }

  void _restoreRecoveredBoard() {
    if (_recoverableProject != null) {
      ref
          .read(whiteboardControllerProvider.notifier)
          .loadProject(_recoverableProject!);
      setState(() {
        _recoverableProject = null;
      });
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const WhiteboardScreen()))
          .then((_) => _loadData());
    }
  }

  Future<void> _dismissRecoveredBoard() async {
    final recovery = ref.read(recoveryServiceProvider);
    await recovery.clearRecoveryDraft();
    setState(() {
      _recoverableProject = null;
    });
  }

  Future<void> _deleteBoard(String projectId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Whiteboard?'),
        content: const Text(
          'Are you sure you want to delete this board? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(projectStorageProvider).deleteProject(projectId);
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/brand/chalkwise_logo.png',
              width: 34,
              height: 34,
              semanticLabel: 'Chalkwise logo',
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chalkwise',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  'AI Whiteboard',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width >= 600)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text(
                'Import PDF',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              onPressed: _importPdf,
            )
          else
            IconButton(
              tooltip: 'Import PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _importPdf,
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'New Board',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            onPressed: () => _openNewBoard(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, size: 20),
            tooltip: 'Welcome tour',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (ctx) =>
                    OnboardingScreen(onDone: () => Navigator.of(ctx).pop()),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Recovery Notification Banner if applicable
              if (_recoverableProject != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF261E14)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF78350F)
                          : const Color(0xFFFDE68A),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.restore_rounded,
                        color: Color(0xFFD97706),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Unsaved draft from previous session is available.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFFFCD34D)
                                : const Color(0xFF92400E),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _restoreRecoveredBoard,
                        child: const Text(
                          'Restore',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: _dismissRecoveredBoard,
                      ),
                    ],
                  ),
                ),
              ],

              // 2. Quick Starter Templates Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Canvas Templates',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    'Instant Start',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _TemplateCard(
                      title: 'Blank Paper',
                      subtitle: 'Clean drafting space',
                      icon: Icons.check_box_outline_blank_rounded,
                      onTap: () => _openNewBoard(
                        initialBackground: const CanvasBackground(
                          style: BackgroundStyle.plain,
                          colorValue: 0xFFFFFFFF,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TemplateCard(
                      title: 'Ruled Notebook',
                      subtitle: 'Writing lines with margin',
                      icon: Icons.format_align_justify_rounded,
                      onTap: () => _openNewBoard(
                        initialBackground: const CanvasBackground(
                          style: BackgroundStyle.ruled,
                          colorValue: 0xFFFFFFFF,
                          spacing: 32.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TemplateCard(
                      title: 'Graph Paper',
                      subtitle: 'Math & coordinate grid',
                      icon: Icons.grid_4x4_rounded,
                      onTap: () => _openNewBoard(
                        initialBackground: const CanvasBackground(
                          style: BackgroundStyle.graph,
                          colorValue: 0xFFFFFFFF,
                          spacing: 24.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TemplateCard(
                      title: 'Studio Slate',
                      subtitle: 'Deep obsidian surface',
                      icon: Icons.contrast_rounded,
                      onTap: () => _openNewBoard(
                        initialBackground: const CanvasBackground(
                          style: BackgroundStyle.plain,
                          colorValue: 0xFF13151A,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TemplateCard(
                      title: 'Classroom Green',
                      subtitle: 'Classic chalkboard',
                      icon: Icons.dashboard_rounded,
                      onTap: () => _openNewBoard(
                        initialBackground: const CanvasBackground(
                          style: BackgroundStyle.plain,
                          colorValue: 0xFF182A22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 4. Recent Whiteboards List
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Lessons',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (_recentProjects.isNotEmpty)
                    Text(
                      '${_recentProjects.length} boards',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_recentProjects.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 40,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1F2937)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.dashboard_customize_outlined,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No saved whiteboards yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tap "New Whiteboard" above to start your first lesson.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentProjects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) {
                    final project = _recentProjects[idx];
                    return _ProjectListItem(
                      project: project,
                      onTap: () => _openExistingBoard(project),
                      onDelete: () => _deleteBoard(project.id),
                    );
                  },
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF181B22) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF262A34) : const Color(0xFFE2E0D9),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectListItem extends StatelessWidget {
  final ProjectModel project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProjectListItem({
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat('MMM d, y • h:mm a').format(project.updatedAt);
    final firstPage = project.pages.isNotEmpty
        ? project.pages.first
        : const PageModel(id: '', pageNumber: 1);

    return Material(
      color: isDark ? const Color(0xFF181B22) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF262A34) : const Color(0xFFE2E0D9),
            ),
          ),
          child: Row(
            children: [
              // Visual preview indicator with background color
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: firstPage.background.color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2E333F)
                        : const Color(0xFFD6D3CC),
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.edit_note_rounded,
                    size: 20,
                    color: firstPage.background.isDark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: -0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF262A34)
                                : const Color(0xFFEAE8E2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${project.totalPages} ${project.totalPages == 1 ? 'page' : 'pages'}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 18,
                ),
                tooltip: 'Delete Board',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
