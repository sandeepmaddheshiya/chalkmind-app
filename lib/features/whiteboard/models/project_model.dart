import 'package:uuid/uuid.dart';
import 'background_style.dart';
import 'page_model.dart';

class ProjectModel {
  /// v2: strokes store points as a compact flat `pts` array. v1 files (with
  /// `points` object lists) are still read transparently.
  static const int currentDocumentVersion = 2;

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int documentVersion;
  final List<PageModel> pages;
  final int currentPageIndex;
  final String? thumbnailPath;
  final bool recoveryStatus;

  /// True for a lightweight listing copy (pages without any drawing), used by
  /// the home screen. Summaries must never be opened or saved as boards.
  final bool isSummary;

  const ProjectModel({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.documentVersion = 1,
    required this.pages,
    this.currentPageIndex = 0,
    this.thumbnailPath,
    this.recoveryStatus = false,
    this.isSummary = false,
  });

  PageModel get currentPage {
    if (pages.isEmpty) {
      return PageModel(id: const Uuid().v4(), pageNumber: 1);
    }
    final index = currentPageIndex.clamp(0, pages.length - 1);
    return pages[index];
  }

  int get totalPages => pages.length;

  ProjectModel copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? documentVersion,
    List<PageModel>? pages,
    int? currentPageIndex,
    String? thumbnailPath,
    bool? recoveryStatus,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      documentVersion: documentVersion ?? this.documentVersion,
      pages: pages ?? this.pages,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      recoveryStatus: recoveryStatus ?? this.recoveryStatus,
      isSummary: isSummary,
    );
  }

  static ProjectModel createEmpty({String? title}) {
    final now = DateTime.now();
    const uuid = Uuid();
    return ProjectModel(
      id: uuid.v4(),
      title:
          title ??
          'Lesson ${now.day}/${now.month} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      createdAt: now,
      updatedAt: now,
      documentVersion: 1,
      pages: [
        PageModel(
          id: uuid.v4(),
          pageNumber: 1,
          background: const CanvasBackground(),
        ),
      ],
      currentPageIndex: 0,
    );
  }

  /// Lightweight copy for listings: page settings and PDF references are
  /// kept; strokes, shapes, texts and graphs are dropped.
  ProjectModel summary() => ProjectModel(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        documentVersion: documentVersion,
        pages: [
          for (final p in pages)
            PageModel(id: p.id, pageNumber: p.pageNumber, background: p.background, pdf: p.pdf),
        ],
        currentPageIndex: currentPageIndex,
        thumbnailPath: thumbnailPath,
        recoveryStatus: recoveryStatus,
        isSummary: true,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'documentVersion': currentDocumentVersion,
    'pages': pages.map((p) => p.toJson()).toList(),
    'currentPageIndex': currentPageIndex,
    'thumbnailPath': thumbnailPath,
    'recoveryStatus': recoveryStatus,
    if (isSummary) 'isSummary': true,
  };

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled Whiteboard',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      documentVersion: json['documentVersion'] as int? ?? 1,
      pages:
          (json['pages'] as List<dynamic>?)
              ?.map((p) => PageModel.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [PageModel(id: const Uuid().v4(), pageNumber: 1)],
      currentPageIndex: json['currentPageIndex'] as int? ?? 0,
      thumbnailPath: json['thumbnailPath'] as String?,
      recoveryStatus: json['recoveryStatus'] as bool? ?? false,
      isSummary: json['isSummary'] as bool? ?? false,
    );
  }
}
