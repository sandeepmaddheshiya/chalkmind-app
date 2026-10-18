import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/whiteboard/models/project_model.dart';

class RecoveryService {
  static const String _recoveryFileName = 'recovery_draft.json';
  Timer? _debounceTimer;

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
  Future<void> saveRecoveryDraft(ProjectModel project) async {
    try {
      final file = await _getRecoveryFile();
      final markedProject = project.copyWith(
        recoveryStatus: true,
        updatedAt: DateTime.now(),
      );
      final jsonString = jsonEncode(markedProject.toJson());
      await file.writeAsString(jsonString, flush: true);
    } catch (e) {
      debugPrint('Error saving recovery draft: $e');
    }
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
      final map = jsonDecode(content) as Map<String, dynamic>;
      return ProjectModel.fromJson(map);
    } catch (e) {
      debugPrint('Error reading recovery draft: $e');
      return null;
    }
  }

  /// Clear recovery draft when project is cleanly saved or closed
  Future<void> clearRecoveryDraft() async {
    try {
      _debounceTimer?.cancel();
      final file = await _getRecoveryFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error clearing recovery draft: $e');
    }
  }
}
