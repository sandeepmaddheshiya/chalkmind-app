import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/whiteboard/models/project_model.dart';
import 'project_storage_service.dart' show encodeProjectJson, decodeProjectJson;

class RecoveryService {
  static const String _recoveryFileName = 'recovery_draft.json';
  Timer? _debounceTimer;
  Future<void> _writeChain = Future.value();
  // Bumped on clear so an in-flight draft write can't resurrect a draft
  // after the project was cleanly saved.
  int _generation = 0;

  Future<File> _getRecoveryFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/$_recoveryFileName');
  }

  /// Debounced write to crash recovery buffer (saves 1s after last change)
  void scheduleRecoverySave(ProjectModel project) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      await saveRecoveryDraft(project);
    });
  }

  /// Immediately write draft to disk
  Future<void> saveRecoveryDraft(ProjectModel project) {
    final gen = _generation;
    final json = project
        .copyWith(recoveryStatus: true, updatedAt: DateTime.now())
        .toJson();
    final next = _writeChain.then((_) async {
      try {
        final bytes = await compute(encodeProjectJson, json);
        if (gen != _generation) return; // cleared meanwhile
        final file = await _getRecoveryFile();
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        if (gen != _generation) {
          await tmp.delete();
          return;
        }
        await tmp.rename(file.path);
      } catch (e) {
        debugPrint('Error saving recovery draft: $e');
      }
    });
    _writeChain = next;
    return next;
  }

  /// Check if a recoverable draft exists
  Future<bool> hasRecoverableSession() async {
    try {
      final file = await _getRecoveryFile();
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// Load recoverable draft
  Future<ProjectModel?> loadRecoveryDraft() async {
    try {
      final file = await _getRecoveryFile();
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return await compute(decodeProjectJson, content);
    } catch (e) {
      debugPrint('Error reading recovery draft: $e');
      return null;
    }
  }

  /// Clear recovery draft when project is cleanly saved or closed
  Future<void> clearRecoveryDraft() async {
    try {
      _debounceTimer?.cancel();
      _generation++;
      await _writeChain;
      final file = await _getRecoveryFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error clearing recovery draft: $e');
    }
  }
}
