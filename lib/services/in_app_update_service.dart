import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dio_client.dart';

class InAppUpdateService {
  static final InAppUpdateService _instance = InAppUpdateService._internal();
  factory InAppUpdateService() => _instance;
  InAppUpdateService._internal();

  final Dio _dio = DioClient.dio;
  String? _currentVersion;
  bool _isChecking = false;
  bool _isUpdating = false;
  bool _forceDialogVisible = false;

  String? get currentVersion => _currentVersion;
  bool get isChecking => _isChecking;
  bool get isUpdating => _isUpdating;

  Future<void> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      debugPrint('InAppUpdateService: Current version $_currentVersion');
    } catch (e) {
      debugPrint('InAppUpdateService: Failed to get package info - $e');
    }
  }

  Future<Map<String, dynamic>?> checkForUpdate({String appType = 'driver'}) async {
    if (_isChecking) return null;
    _isChecking = true;
    try {
      final response = await _dio.get(
        '/api/app-settings/version',
        queryParameters: {
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'app_type': appType,
        },
      );

      if (response.statusCode == 200 && response.data is Map && response.data['success'] == true) {
        final data = response.data['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      debugPrint('InAppUpdateService: Error checking for updates - $e');
      return null;
    } finally {
      _isChecking = false;
    }
  }

  bool _isTruthy(dynamic value) {
    if (value == true) return true;
    if (value == false || value == null) return false;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'on';
  }

  bool isForceUpdateRequired(Map<String, dynamic> updateData) {
    final current = (_currentVersion ?? '1.0.0').trim();
    final minSupported = (updateData['minimum_supported_version'] ?? '1.0.0').toString().trim();
    final latest = (updateData['current_version'] ?? updateData['latest_version'] ?? '1.0.0').toString().trim();
    final updatesEnabled = updateData['enable_in_app_updates'] != false &&
        updateData['enable_in_app_updates']?.toString().toLowerCase() != 'false';
    final forceFlag = _isTruthy(updateData['force_update']) || _isTruthy(updateData['forceUpdate']);

    // Always block clients older than the configured minimum.
    if (_isVersionBelowMinimum(current, minSupported)) return true;

    // Force-to-latest only when in-app updates are enabled and force is ON.
    if (updatesEnabled && forceFlag && _isUpdateAvailable(current, latest)) return true;
    return false;
  }

  Future<bool> openStore(Map<String, dynamic> updateData, {required String appType}) async {
    try {
      final playUrl = (updateData['play_store_url'] ?? '').toString().trim();
      final appStoreUrl = (updateData['app_store_url'] ?? '').toString().trim();
      final packageName = (updateData['android_package'] ??
              (appType == 'driver' ? 'com.vitecaptain.driver' : 'com.vitevikle.customer.ride'))
          .toString()
          .trim();

      Uri uri;
      if (Platform.isAndroid) {
        uri = Uri.parse(playUrl.isNotEmpty
            ? playUrl
            : 'https://play.google.com/store/apps/details?id=$packageName');
      } else if (Platform.isIOS && appStoreUrl.isNotEmpty) {
        uri = Uri.parse(appStoreUrl);
      } else {
        uri = Uri.parse(playUrl.isNotEmpty
            ? playUrl
            : 'https://play.google.com/store/apps/details?id=$packageName');
      }

      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      debugPrint('InAppUpdateService: openStore error - $e');
      return false;
    }
  }

  Future<bool> gateAppStart(BuildContext context, {required String appType}) async {
    await initialize();
    final updateData = await checkForUpdate(appType: appType);
    if (updateData == null) return true;
    if (!context.mounted) return true;

    if (_isTruthy(updateData['maintenance_mode'])) {
      await _showBlockingDialog(
        context,
        title: 'Maintenance Mode',
        message: (updateData['maintenance_message'] ??
                'The app is under maintenance. Please try again later.')
            .toString(),
        showUpdateButton: false,
      );
      return false;
    }

    if (isForceUpdateRequired(updateData)) {
      await _showBlockingDialog(
        context,
        title: 'Update Required',
        message: (updateData['force_update_message'] ??
                'A critical update is required. Please update to continue using the app.')
            .toString(),
        showUpdateButton: true,
        onUpdate: () async {
          try {
            if (Platform.isAndroid) {
              final info = await InAppUpdate.checkForUpdate();
              if (info.updateAvailability == UpdateAvailability.updateAvailable) {
                await InAppUpdate.performImmediateUpdate();
                return;
              }
            }
          } catch (_) {}
          await openStore(updateData, appType: appType);
        },
      );
      // Dialog dismissed only via Exit; do not keep re-prompting this session.
      return false;
    }

    final updatesEnabled = updateData['enable_in_app_updates'] != false &&
        updateData['enable_in_app_updates']?.toString().toLowerCase() != 'false';
    if (!updatesEnabled) return true;

    try {
      await performUpdate(updateData: updateData, appType: appType);
    } catch (_) {}
    return true;
  }

  Future<void> _showBlockingDialog(
    BuildContext context, {
    required String title,
    required String message,
    required bool showUpdateButton,
    Future<void> Function()? onUpdate,
  }) async {
    if (_forceDialogVisible) return;
    _forceDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text('Exit'),
                ),
                if (showUpdateButton)
                  FilledButton(
                    onPressed: () async {
                      if (onUpdate != null) await onUpdate();
                    },
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00A651)),
                    child: const Text('Update Now'),
                  ),
              ],
            ),
          );
        },
      );
    } finally {
      _forceDialogVisible = false;
    }
  }

  Future<UpdateResult> performUpdate({
    required Map<String, dynamic> updateData,
    String appType = 'driver',
  }) async {
    if (_isUpdating) return UpdateResult.alreadyInProgress;
    _isUpdating = true;
    try {
      final enableInAppUpdates = updateData['enable_in_app_updates'] != false;
      if (!enableInAppUpdates) return UpdateResult.disabled;

      if (isForceUpdateRequired(updateData)) {
        return UpdateResult.forceUpdateRequired;
      }

      final latestVersion = (updateData['current_version'] ?? '1.0.0').toString();
      if (!_isUpdateAvailable(_currentVersion ?? '1.0.0', latestVersion)) {
        return UpdateResult.noUpdateAvailable;
      }

      final enableImmediate = updateData['enable_immediate_update'] != false;
      final enableFlexible = updateData['enable_flexible_update'] == true;

      if (!Platform.isAndroid) return UpdateResult.disabled;

      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability == UpdateAvailability.updateNotAvailable) {
        return UpdateResult.noUpdateAvailable;
      }
      if (updateInfo.updateAvailability == UpdateAvailability.unknown) {
        return UpdateResult.notPlayStoreInstall;
      }

      if (enableImmediate) {
        await InAppUpdate.performImmediateUpdate();
        return UpdateResult.success;
      }
      if (enableFlexible) {
        await InAppUpdate.startFlexibleUpdate();
        return UpdateResult.flexibleUpdateStarted;
      }
      return UpdateResult.disabled;
    } catch (e) {
      debugPrint('InAppUpdateService: Error performing update - $e');
      return UpdateResult.error;
    } finally {
      _isUpdating = false;
    }
  }

  bool _isUpdateAvailable(String current, String latest) {
    return _compareVersions(current, latest) < 0;
  }

  bool _isVersionBelowMinimum(String current, String minimum) {
    return _compareVersions(current, minimum) < 0;
  }

  int _compareVersions(String a, String b) {
    try {
      final left = a.split(RegExp(r'[^0-9]+')).where((e) => e.isNotEmpty).map(int.parse).toList();
      final right = b.split(RegExp(r'[^0-9]+')).where((e) => e.isNotEmpty).map(int.parse).toList();
      final len = left.length > right.length ? left.length : right.length;
      for (int i = 0; i < len; i++) {
        final l = i < left.length ? left[i] : 0;
        final r = i < right.length ? right[i] : 0;
        if (l < r) return -1;
        if (l > r) return 1;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}

enum UpdateResult {
  success,
  flexibleUpdateStarted,
  noUpdateAvailable,
  alreadyInProgress,
  disabled,
  notPlayStoreInstall,
  forceUpdateRequired,
  maintenanceMode,
  error,
}
