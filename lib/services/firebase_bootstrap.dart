import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Starts Firebase when the platform config exists.
/// On iOS that file is ios/Runner/GoogleService-Info.plist.
/// The captain app still opens if that file has not been added yet.
Future<bool> ensureFirebase() async {
  if (Firebase.apps.isNotEmpty) return true;
  try {
    await Firebase.initializeApp();
    return true;
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
    return false;
  }
}
