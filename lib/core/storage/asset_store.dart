import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Stores large binary assets (rendered PDF pages, word indexes) as files in
/// the app documents directory, referenced from projects by relative path.
///
/// Relative paths keep projects valid if the platform moves the documents
/// directory (e.g. iOS reinstall).
class AssetStore {
  static const String _dirName = 'boardflow_assets';
  static String? _root;

  /// Absolute root, or null before [init] (e.g. in unit tests).
  static String? get root => _root;

  @visibleForTesting
  static set rootForTesting(String? value) => _root = value;

  /// Call once at startup.
  static Future<void> init() async {
    if (_root != null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/$_dirName');
      if (!await dir.exists()) await dir.create(recursive: true);
      _root = dir.path;
    } catch (e) {
      debugPrint('AssetStore: unavailable ($e)');
    }
  }

  /// Absolute path for a stored relative path, or null if unavailable.
  static String? resolve(String relativePath) =>
      _root == null ? null : '$_root/$relativePath';

  /// Directory for one imported document's files (created if missing).
  static Future<Directory> docDir(String docId) async {
    await init();
    if (_root == null) throw StateError('Asset storage is unavailable');
    final dir = Directory('$_root/$docId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Deletes an imported document's files (when its project is deleted).
  static Future<void> deleteDoc(String docId) async {
    // docIds are generated UUIDs; refuse anything that could escape the root.
    if (_root == null ||
        docId.isEmpty ||
        docId.contains('/') ||
        docId.contains('..')) {
      return;
    }
    final dir = Directory('$_root/$docId');
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('AssetStore: could not delete $docId: $e');
    }
  }
}
