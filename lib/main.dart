import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/splash_screen.dart';
import 'package:vite_captain/providers/app_settings_provider.dart';
import 'package:vite_captain/services/parcel_activity_state.dart';

import 'providers/auth_provider.dart';
import 'providers/driver_auth_provider.dart';
import 'providers/document_verification_provider.dart';
import 'providers/driver_status_summary_provider.dart';
import 'services/ride_booking_state.dart';
import 'services/chat_notification_provider.dart';
import 'services/notification_service.dart';
import 'services/session_service.dart';
import 'screens/app_settings_screen.dart';
import 'screens/policy_screen.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  if (Platform.isAndroid) {
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  runApp(const ViteWayApp(home: BootstrapScreen()));
}

class ViteWayApp extends StatelessWidget {
  final Widget home;

  const ViteWayApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RideBookingState>(create: (_) => RideBookingState()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<DriverAuthProvider>(create: (_) => DriverAuthProvider()),
        ChangeNotifierProvider<DocumentVerificationProvider>(create: (_) => DocumentVerificationProvider()),
        ChangeNotifierProvider<DriverStatusSummaryProvider>(create: (_) => DriverStatusSummaryProvider()),
        ChangeNotifierProvider<ChatNotificationProvider>(create: (_) => ChatNotificationProvider()),
        ChangeNotifierProvider<AppSettingsProvider>(create: (_) => AppSettingsProvider()),
        ChangeNotifierProvider<ParcelActivityState>(create: (_) => ParcelActivityState()),
      ],
      child: Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              try {
                await context.read<ParcelActivityState>().hydrate();
              } catch (_) {}

              final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
              if (driverId.isNotEmpty && context.mounted) {
                await context.read<ChatNotificationProvider>().init(receiverId: driverId, receiverRole: 'driver');
                final notif = NotificationService();
                notif.onNotificationTap = (data) {
                  // Return to home; HomeMapScreen restores and opens the correct ride screen.
                  navigatorKey.currentState?.popUntil((route) => route.isFirst);
                };
                await notif.init(driverId: driverId);
              }
            } catch (_) {}
          });

          return Consumer<AppSettingsProvider>(
            builder: (context, appSettings, _) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: "Vite Captain",
                navigatorKey: navigatorKey,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: ThemeMode.light,
                locale: appSettings.locale,
                supportedLocales: const [
                  Locale('en'),
                  Locale('hi'),
                  Locale('pa'),
                ],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                routes: {
                  '/app-settings': (_) => const AppSettingsScreen(),
                  '/privacy-policy': (_) => const PolicyScreen(type: 'privacy'),
                  '/terms-condition': (_) => const PolicyScreen(type: 'terms'),
                },
                home: home,
              );
            },
          );
        },
      ),
    );
  }
}
