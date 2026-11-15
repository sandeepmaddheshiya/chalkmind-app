import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

class ShareService {
  /// Open system share sheet with an exported file
  static Future<void> shareFile({
    required File file,
    String? subject,
    String? text,
  }) async {
    try {
      final xFile = XFile(file.path);
      await SharePlus.instance.share(
        ShareParams(files: [xFile], subject: subject, text: text),
      );
    } catch (e) {
      debugPrint('Error invoking system share: $e');
    }
  }
}
