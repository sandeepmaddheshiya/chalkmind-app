import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/whiteboard/models/project_model.dart';

class ProjectStorageService {
  static const String _projectsDirName = 'boardflow_projects';
  static const String _projectExtension = '.bf';

  Future<Directory> _getProjectsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectsDir = Directory('${appDir.path}/$_projectsDirName');
    if (!await projectsDir.exists()) {
      await projectsDir.create(recursive: true);
    }
    return projectsDir;
  }

  /// Atomically save project to disk with .tmp staging
  Future<void> saveProject(ProjectModel project) async {
    try {
      final dir = await _getProjectsDirectory();
      final targetFile = File('${dir.path}/${project.id}$_projectExtension');
      final tempFile = File('${dir.path}/${project.id}.tmp');

      final jsonString = jsonEncode(project.toJson());

      // Write to temp file first
      await tempFile.writeAsString(jsonString, flush: true);

      // Atomic rename to final target
      if (await tempFile.exists()) {
        await tempFile.rename(targetFile.path);
      }
    } catch (e, stack) {
      debugPrint('Error saving project ${project.id}: $e\n$stack');
      rethrow;
    }
  }

  /// Load a single project by ID
  Future<ProjectModel?> loadProject(String projectId) async {
    try {
      final dir = await _getProjectsDirectory();
      final file = File('${dir.path}/$projectId$_projectExtension');
      if (!await file.exists()) return null;

      final jsonString = await file.readAsString();
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return ProjectModel.fromJson(jsonMap);
    } catch (e, stack) {
      debugPrint('Error loading project $projectId: $e\n$stack');
      return null;
    }
  }

  /// List all local saved projects sorted by last updated
  Future<List<ProjectModel>> listProjects() async {
    try {
      final dir = await _getProjectsDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(_projectExtension))
          .toList();

      final List<ProjectModel> projects = [];
      for (final file in files) {
        try {
          final content = await file.readAsString();
          final map = jsonDecode(content) as Map<String, dynamic>;
          projects.add(ProjectModel.fromJson(map));
        } catch (e) {
          debugPrint('Skipping corrupted file ${file.path}: $e');
        }
      }

      projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return projects;
    } catch (e) {
      debugPrint('Error listing projects: $e');
      return [];
    }
  }

  /// Delete project file
  Future<bool> deleteProject(String projectId) async {
    try {
      final dir = await _getProjectsDirectory();
      final file = File('${dir.path}/$projectId$_projectExtension');
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting project $projectId: $e');
      return false;
    }
  }
}
