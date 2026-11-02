import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vite_captain/maps/mappls_map.dart';

/// Opens turn-by-turn navigation in the Mappls app.
Future<bool> openMapplsNavigation(
  LatLng destination, {
  List<LatLng> waypoints = const <LatLng>[],
}) async {
  final places = <String>[
    ...waypoints.map((point) => '${point.latitude},${point.longitude}'),
    '${destination.latitude},${destination.longitude}',
  ].join(';');
  final schemeUri = Uri.parse('mappls://navigation?places=$places');
  final appUri = Uri.parse('https://mappls.com/navigation?places=$places');

  if (Platform.isAndroid) {
    for (final target in <String>[schemeUri.toString(), appUri.toString()]) {
      try {
        await AndroidIntent(
          action: 'action_view',
          data: target,
          package: 'com.mmi.maps',
        ).launch();
        return true;
      } catch (_) {}
    }
  }

  try {
    final opened = await launchUrl(schemeUri, mode: LaunchMode.externalApplication);
    if (opened) return true;
  } catch (_) {}

  try {
    await launchUrl(
      Uri.parse('https://play.google.com/store/apps/details?id=com.mmi.maps'),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}
  return false;
}

/// Opens Mappls for a written address when coordinates are not available.
Future<bool> openMapplsPlace(String address) async {
  final query = address.trim();
  if (query.isEmpty) return false;
  final appUri = Uri.parse('https://mappls.com/search?query=${Uri.encodeComponent(query)}');

  if (Platform.isAndroid) {
    try {
      await AndroidIntent(
        action: 'action_view',
        data: appUri.toString(),
        package: 'com.mmi.maps',
      ).launch();
      return true;
    } catch (_) {}
  }

  try {
    return await launchUrl(appUri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
