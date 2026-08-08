import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class ProfileController {
  static final ValueNotifier<String?> profileImagePath = ValueNotifier<String?>(null);

  static void updateProfileImage(String path) {
    profileImagePath.value = path;
  }

  static void clearProfileImage() {
    profileImagePath.value = null;
  }

  static ImageProvider? imageProviderOrNull() {
    final path = profileImagePath.value;
    if (path == null || path.trim().isEmpty) return null;

    final trimmed = path.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return NetworkImage(trimmed);
    }

    final file = File(trimmed);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }
}
