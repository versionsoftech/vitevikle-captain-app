import 'package:flutter/material.dart';
import 'package:vite_captain/screens/profile_screen.dart';
import 'package:vite_captain/screens/my_rating_screen.dart';
import 'package:vite_captain/screens/payments_screen.dart';
import 'package:vite_captain/screens/ride_history_screen.dart';
import 'package:vite_captain/screens/settings_screen.dart';
import 'package:vite_captain/screens/safety_toolkit_screen.dart';
import 'package:vite_captain/screens/notifications_screen.dart';
import 'package:vite_captain/screens/refer_friends_screen.dart';
import 'package:vite_captain/screens/menu/claims_screen.dart';
import 'package:vite_captain/screens/wallet/wallet_screen.dart';
import 'package:vite_captain/controllers/profile_controller.dart';
import 'package:vite_captain/screens/personal_picture/personal_picture_instruction_screen.dart';
import 'package:vite_captain/services/session_service.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  late Future<Map<String, String>> _userBasicsFuture;

  @override
  void initState() {
    super.initState();
    _userBasicsFuture = const SessionService().getUserBasics(forceRefresh: true);
  }

  Widget menuItem(
    IconData icon,
    String title, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 22, color: Colors.grey[700]),
                const SizedBox(width: 16),
                Expanded(
                  child: subtitle == null
                      ? Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 0.5,
          color: Colors.grey.shade300,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Menu"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),

      body: ListView(
        children: [

          /// PROFILE CARD
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );

                    if (!mounted) return;
                    setState(() {
                      _userBasicsFuture =
                          const SessionService().getUserBasics(forceRefresh: true);
                    });
                  },
                  child: Row(
                    children: [
                      ValueListenableBuilder<String?>(
                        valueListenable: ProfileController.profileImagePath,
                        builder: (context, _, __) {
                          final pickedProvider = ProfileController.imageProviderOrNull();

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PersonalPictureInstructionScreen(),
                                ),
                              );
                            },
                            child: FutureBuilder<Map<String, String>>(
                              future: _userBasicsFuture,
                              builder: (context, snapshot) {
                                final data = snapshot.data ?? const <String, String>{};
                                final imageUrl = (data['imageUrl'] ?? '').trim();

                                if (pickedProvider != null) {
                                  return CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Colors.grey.shade200,
                                    backgroundImage: pickedProvider,
                                  );
                                }

                                if (imageUrl.isNotEmpty) {
                                  return ClipOval(
                                    child: Image.network(
                                      imageUrl,
                                      key: ValueKey(imageUrl),
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      headers: const {'Cache-Control': 'no-cache'},
                                      errorBuilder: (context, error, stackTrace) {
                                        return CircleAvatar(
                                          radius: 22,
                                          backgroundColor: Colors.grey.shade200,
                                          child: const Icon(Icons.person, color: Colors.grey),
                                        );
                                      },
                                    ),
                                  );
                                }

                                return CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Colors.grey.shade200,
                                  child: const Icon(Icons.person, color: Colors.grey),
                                );
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FutureBuilder<Map<String, String>>(
                          future: _userBasicsFuture,
                          builder: (context, snapshot) {
                            final data = snapshot.data ?? const <String, String>{};
                            final name = (data['name'] ?? '').trim();
                            final mobile = (data['mobile'] ?? '').trim();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isNotEmpty ? name : '-',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  mobile.isNotEmpty ? mobile : '-',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
                Divider(
                  height: 24,
                  thickness: 1,
                  color: Colors.grey.shade200,
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MyRatingScreen(),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "5.00 My Rating",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ],
            ),
          ),

          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WalletScreen(),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF369D01),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "My Wallet Balance",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    "₹ 0.00",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          menuItem(Icons.help_outline, "Help"),
          menuItem(
            Icons.payment,
            "Payment",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PaymentsScreen(),
                ),
              );
            },
          ),
          menuItem(
            Icons.history,
            "My Rides",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RideHistoryScreen(),
                ),
              );
            },
          ),
          menuItem(
            Icons.security,
            "Safety",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SafetyToolkitScreen(),
                ),
              );
            },
          ),
          menuItem(
            Icons.card_giftcard,
            "Refer and Earn",
            subtitle: "Get ₹50",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ReferFriendsScreen(),
                ),
              );
            },
          ),
          menuItem(
            Icons.notifications,
            "Notifications",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationsScreen(),
                ),
              );
            },
          ),
          menuItem(
            Icons.shield,
            "Claims",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ClaimsScreen(),
                ),
              );
            },
          ),
          menuItem(
            Icons.settings,
            "Settings",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Earn money with ViteVikle",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "Become a Captain!",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    "assets/images/menu/menu.jpg",
                    width: 110,
                    height: 70,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }
}
