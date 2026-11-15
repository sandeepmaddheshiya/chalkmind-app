import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/whiteboard/models/project_model.dart';
import 'asset_store.dart';

/// Top-level so they can run in a background isolate via [compute].
List<int> encodeProjectJson(Map<String, dynamic> json) =>
    utf8.encode(jsonEncode(json));
ProjectModel decodeProjectJson(String content) =>
    ProjectModel.fromJson(jsonDecode(content) as Map<String, dynamic>);

/// Lists boards for the home screen from small `.meta` summary files
/// (title, date, pages) instead of decoding every board's full drawing.
/// Boards saved by older versions get a summary written on first listing.
/// Runs in a background isolate; unreadable files are skipped.
List<ProjectModel> listProjectSummaries(List<String> boardPaths) {
  final out = <ProjectModel>[];
  for (final path in boardPaths) {
    try {
      final board = File(path);
      final meta = File(metaPathFor(path));
      if (meta.existsSync() && !meta.lastModifiedSync().isBefore(board.lastModifiedSync())) {
        out.add(decodeProjectJson(meta.readAsStringSync()));
        continue;
      }
      final summary = decodeProjectJson(board.readAsStringSync()).summary();
      try {
        meta.writeAsStringSync(jsonEncode(summary.toJson()));
      } catch (_) {}
      out.add(summary);
    } catch (e) {
      debugPrint('Skipping unreadable board $path: $e');
    }
  }
  return out;
}

String metaPathFor(String boardPath) =>
    '${boardPath.substring(0, boardPath.length - '.bf'.length)}.meta';

class ProjectStorageService {
  // Serializes writes so two saves never race on the same .tmp file.
  Future<void> _writeChain = Future.value();

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
  /// JSON encoding runs off the UI thread so saving a large board doesn't
  /// drop frames while the teacher is drawing.
  Future<void> saveProject(ProjectModel project) {
    // A listing summary has no drawing: saving it would wipe the board.
    if (project.isSummary) {
      return Future.error(StateError('Refusing to save a board summary over the full board'));
    }
    // Build the map synchronously (cheap) so later edits can't race the save.
    final json = project.toJson();
    final summaryJson = project.summary().toJson(); // tiny: no drawing data
    final next = _writeChain.then((_) => _write(project.id, json, summaryJson));
    _writeChain = next.catchError((_) {});
    return next;
  }

  Future<void> _write(String id, Map<String, dynamic> json, Map<String, dynamic> summaryJson) async {
    try {
      final dir = await _getProjectsDirectory();
      final targetFile = File('${dir.path}/$id$_projectExtension');
      final tempFile = File('${dir.path}/$id.tmp');

      final bytes = await compute(encodeProjectJson, json);

      // Write to temp file first, then atomically rename over the target.
      await tempFile.writeAsBytes(bytes, flush: true);
      await tempFile.rename(targetFile.path);

      // Small summary for the home screen list (written after the board so
      // it is never newer than a board it doesn't match).
      try {
        await File(metaPathFor(targetFile.path)).writeAsString(jsonEncode(summaryJson));
      } catch (e) {
        debugPrint('Could not write summary for $id: $e');
      }
    } catch (e, stack) {
      debugPrint('Error saving project $id: $e\n$stack');
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
      return await compute(decodeProjectJson, jsonString);
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

      // Read and decode every board in ONE background isolate. (One isolate
      // per board paid the isolate start-up cost N times.)
      final projects = await compute(listProjectSummaries, [for (final f in files) f.path]);

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
        // Remove imported PDF assets owned by this board.
        try {
          final project = await compute(
            decodeProjectJson,
            await file.readAsString(),
          );
          final docIds = {
            for (final p in project.pages)
              if (p.pdf != null) p.pdf!.docId,
          };
          for (final id in docIds) {
            await AssetStore.deleteDoc(id);
          }
        } catch (e) {
          debugPrint('Could not clean assets for $projectId: $e');
        }
        await file.delete();
        final meta = File(metaPathFor(file.path));
        if (await meta.exists()) await meta.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting project $projectId: $e');
      return false;
    }
  }
}
