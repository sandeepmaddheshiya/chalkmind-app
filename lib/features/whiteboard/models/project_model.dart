import 'package:uuid/uuid.dart';
import 'background_style.dart';
import 'page_model.dart';

class ProjectModel {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int documentVersion;
  final List<PageModel> pages;
  final int currentPageIndex;
  final String? thumbnailPath;
  final bool recoveryStatus;

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
    );
  }

  static ProjectModel createEmpty({String? title}) {
    final now = DateTime.now();
    const uuid = Uuid();
    return ProjectModel(
      id: uuid.v4(),
      title: title ?? 'Lesson ${now.day}/${now.month} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'documentVersion': documentVersion,
    'pages': pages.map((p) => p.toJson()).toList(),
    'currentPageIndex': currentPageIndex,
    'thumbnailPath': thumbnailPath,
    'recoveryStatus': recoveryStatus,
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
      pages: (json['pages'] as List<dynamic>?)
              ?.map((p) => PageModel.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [
            PageModel(
              id: const Uuid().v4(),
              pageNumber: 1,
            )
          ],
      currentPageIndex: json['currentPageIndex'] as int? ?? 0,
      thumbnailPath: json['thumbnailPath'] as String?,
      recoveryStatus: json['recoveryStatus'] as bool? ?? false,
    );
  }
}
