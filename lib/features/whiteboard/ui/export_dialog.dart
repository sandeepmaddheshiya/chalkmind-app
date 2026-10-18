import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/export/export_service.dart';
import '../../../core/export/share_service.dart';
import '../state/whiteboard_notifier.dart';

class ExportDialog extends ConsumerStatefulWidget {
  const ExportDialog({super.key});

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

enum ExportFormat { pdf, png }

class _ExportDialogState extends ConsumerState<ExportDialog> {
  ExportFormat _selectedFormat = ExportFormat.pdf;
  bool _isExporting = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardControllerProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Export & Share Lesson'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Board: "${state.project.title}"',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text(
              'Choose Format:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),

            // Format Option 1: PDF Document
            _ExportFormatCard(
              title: 'Multi-Page PDF Document',
              subtitle: 'Complete lesson with all ${state.project.totalPages} pages for students and classrooms.',
              icon: Icons.picture_as_pdf_rounded,
              iconColor: Colors.red,
              isSelected: _selectedFormat == ExportFormat.pdf,
              onTap: _isExporting
                  ? null
                  : () => setState(() => _selectedFormat = ExportFormat.pdf),
            ),
            const SizedBox(height: 10),

            // Format Option 2: High-Res PNG Image
            _ExportFormatCard(
              title: 'High-Res PNG Image',
              subtitle: 'Crisp snapshot of current page ${state.project.currentPageIndex + 1}.',
              icon: Icons.image_rounded,
              iconColor: theme.colorScheme.primary,
              isSelected: _selectedFormat == ExportFormat.png,
              onTap: _isExporting
                  ? null
                  : () => setState(() => _selectedFormat = ExportFormat.png),
            ),

            if (_isExporting) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _statusMessage ?? 'Preparing export...',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text('Share Lesson'),
          onPressed: _isExporting ? null : _handleExportAndShare,
        ),
      ],
    );
  }

  Future<void> _handleExportAndShare() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'Rendering lesson pages...';
    });

    try {
      final state = ref.read(whiteboardControllerProvider);
      final sanitizedTitle = state.project.title
          .replaceAll(RegExp(r'[^\w\s\-]'), '_')
          .replaceAll(' ', '_');

      if (_selectedFormat == ExportFormat.pdf) {
        setState(() => _statusMessage = 'Compiling PDF document...');
        final pdfFile = await ExportService.exportProjectAsPdf(
          project: state.project,
          fileName: sanitizedTitle,
        );
        setState(() => _statusMessage = 'Opening share sheet...');
        await ShareService.shareFile(
          file: pdfFile,
          subject: state.project.title,
          text: 'Lesson whiteboard notes: ${state.project.title}',
        );
      } else {
        setState(() => _statusMessage = 'Rendering PNG image...');
        final pngFile = await ExportService.exportPageAsPng(
          page: state.project.currentPage,
          fileName: '${sanitizedTitle}_page_${state.project.currentPageIndex + 1}',
        );
        setState(() => _statusMessage = 'Opening share sheet...');
        await ShareService.shareFile(
          file: pngFile,
          subject: state.project.title,
          text: 'Lesson whiteboard notes: ${state.project.title}',
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lesson shared successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _ExportFormatCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final bool isSelected;
  final VoidCallback? onTap;

  const _ExportFormatCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.1)
          : (isDark ? Colors.grey.shade900 : Colors.grey.shade50),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? theme.colorScheme.primary : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

