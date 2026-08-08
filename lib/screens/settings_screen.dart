import 'package:flutter/material.dart';
import 'package:vite_captain/screens/profile_screen.dart';
import 'package:vite_captain/screens/driver_reviews_screen.dart';
import 'package:vite_captain/screens/wallet/wallet_screen.dart';
import 'package:vite_captain/screens/wallet/driver_withdraw_screen.dart';
import 'package:vite_captain/controllers/profile_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/screens/my_rating_screen.dart';
import 'package:vite_captain/screens/personal_picture/personal_picture_instruction_screen.dart';
import 'package:vite_captain/providers/driver_status_summary_provider.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/screens/vehicle_registration_screen.dart';
import 'package:vite_captain/screens/document_verification_menu_screen.dart';
import 'package:vite_captain/screens/bank_details_screen.dart';
import 'package:vite_captain/widgets/logout_dialog.dart';
import 'package:vite_captain/screens/expiry_history_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  static const SessionService _sessionService = SessionService();

  bool isRideOn = true;
  bool isParcelOn = false;
  bool isIntercityOn = false;

  bool _loadingServiceToggles = false;

  bool _updatingService = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DriverStatusSummaryProvider>().refresh(silent: true);
      _hydrateServiceToggles();
    });
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveToggleCache({
    bool? ride,
    bool? parcel,
    bool? intercity,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (ride != null) await prefs.setBool('is_ride_active', ride);
      if (parcel != null) await prefs.setBool('is_parcel_active', parcel);
      if (intercity != null) await prefs.setBool('is_intercity_active', intercity);
    } catch (_) {}
  }

  Future<void> _loadToggleCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ride = prefs.getBool('is_ride_active');
      final parcel = prefs.getBool('is_parcel_active');
      final intercity = prefs.getBool('is_intercity_active');
      if (!mounted) return;
      setState(() {
        if (ride != null) isRideOn = ride;
        if (parcel != null) isParcelOn = parcel;
        else isParcelOn = true;
        if (intercity != null) isIntercityOn = intercity;
      });
    } catch (_) {}
  }

  Future<void> _hydrateServiceToggles() async {
    if (_loadingServiceToggles) return;
    setState(() {
      _loadingServiceToggles = true;
    });

    await _loadToggleCache();

    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;
      final resp = await const ApiService().getDriverProfile(token: token);
      final ok = resp['success'] == true;
      final data = ok ? resp['data'] : null;
      if (data is! Map) return;

      if (!mounted) return;
      setState(() {
        isRideOn = (data['rideEnabled'] ?? data['is_ride_active'] ?? data['isRideActive'] ?? true) == true;
        isParcelOn = (data['is_parcel_active'] ?? data['isParcelActive'] ?? true) == true;
        isIntercityOn = (data['intercityEnabled'] ?? data['is_intercity_active'] ?? data['isIntercityActive'] ?? false) == true;
      });

      await _saveToggleCache(ride: isRideOn, parcel: isParcelOn, intercity: isIntercityOn);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _loadingServiceToggles = false;
        });
      }
    }
  }

  Widget buildToggle(String title, bool value, Function(bool) onChanged) {
    return ListTile(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
      trailing: Switch(
        value: value,
        activeThumbColor: const Color(0xFF369D01),
        onChanged: (_loadingServiceToggles || _updatingService) ? null : (v) => onChanged(v),
      ),
    );
  }

  Future<bool> updateDriverService(String type, bool status) async {
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return false;
      final resp = await const ApiService().updateDriverServices(token: token, type: type, status: status);
      return resp['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateDriverSettings({
    required bool rideEnabled,
    required bool intercityEnabled,
  }) async {
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return false;
      final resp = await const ApiService().updateDriverSettings(
        token: token,
        rideEnabled: rideEnabled,
        intercityEnabled: intercityEnabled,
      );
      return resp['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onToggleChanged(String type, bool nextValue) async {
    if (_updatingService) return;

    final prevRide = isRideOn;
    final prevParcel = isParcelOn;
    final prevIntercity = isIntercityOn;

    setState(() {
      _updatingService = true;
      if (type == 'ride') isRideOn = nextValue;
      if (type == 'parcel') isParcelOn = nextValue;
      if (type == 'intercity') isIntercityOn = nextValue;
    });

    final ok = (type == 'parcel')
        ? await updateDriverService(type, nextValue)
        : await updateDriverSettings(rideEnabled: isRideOn, intercityEnabled: isIntercityOn);

    if (!mounted) return;

    if (!ok) {
      setState(() {
        isRideOn = prevRide;
        isParcelOn = prevParcel;
        isIntercityOn = prevIntercity;
        _updatingService = false;
      });
      _showErrorMessage('Failed to update service. Please try again.');
      return;
    }

    await _saveToggleCache(
      ride: isRideOn,
      parcel: isParcelOn,
      intercity: isIntercityOn,
    );

    setState(() {
      _updatingService = false;
    });

    final label = type == 'ride'
        ? 'Ride'
        : type == 'parcel'
            ? 'Parcel'
            : 'Intercity';

    _showSuccessMessage(nextValue ? '$label service enabled' : '$label service disabled');
  }

  Widget _statusIcon(VerificationStatus status) {
    switch (status) {
      case VerificationStatus.approved:
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
      case VerificationStatus.rejected:
        return const Icon(Icons.cancel, color: Colors.red, size: 20);
      case VerificationStatus.pending:
        return const Icon(Icons.access_time, color: Colors.orange, size: 20);
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, left: 2, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
    bool showDivider = true,
    Color? iconColor,
    Widget? trailing,
  }) {
    final tile = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F8EF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor ?? const Color(0xFF0A7A40), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );

    if (!showDivider) return tile;
    return Column(
      children: [
        tile,
        Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      ],
    );
  }

  Widget _menuCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _topHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
          ),
        ),
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.notifications_none, color: Colors.black87),
            ),
            const SizedBox(width: 10),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WalletScreen()),
                  );
                },
                icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.black87),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _profileCard(BuildContext context) {
    final future = _sessionService.getUserBasics();

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              );
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
                        future: future,
                        builder: (context, snapshot) {
                          final data = snapshot.data ?? const <String, String>{};
                          final imageUrl = (data['imageUrl'] ?? '').trim();

                          if (pickedProvider != null) {
                            return CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: pickedProvider,
                            );
                          }

                          if (imageUrl.isNotEmpty) {
                            return ClipOval(
                              child: Image.network(
                                imageUrl,
                                key: ValueKey(imageUrl),
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                headers: const {'Cache-Control': 'no-cache'},
                                errorBuilder: (context, error, stackTrace) {
                                  return CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Colors.grey.shade200,
                                    child: const Icon(Icons.person, color: Colors.grey),
                                  );
                                },
                              ),
                            );
                          }

                          return CircleAvatar(
                            radius: 28,
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
                    future: future,
                    builder: (context, snapshot) {
                      final data = snapshot.data ?? const <String, String>{};
                      final name = (data['name'] ?? '').trim();
                      final mobile = (data['mobile'] ?? '').trim();
                      final email = (data['email'] ?? '').trim();
                      final subtitle = mobile.isNotEmpty
                          ? mobile
                          : (email.isNotEmpty ? email : '-');

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
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
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
            child: const Row(
              children: [
                Icon(Icons.star, color: Colors.orange, size: 18),
                SizedBox(width: 6),
                Text(
                  '5.00 My Rating',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Spacer(),
                Icon(Icons.arrow_forward_ios, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F4),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF369D01),
          onRefresh: () => context.read<DriverStatusSummaryProvider>().refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topHeader(),
                  _profileCard(context),

                _sectionTitle('General'),
                _menuCard(
                  children: [
                    _menuTile(
                      icon: Icons.person_outline,
                      title: 'Profile',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ProfileScreen(),
                          ),
                        );
                      },
                    ),
                    _menuTile(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'My Wallet',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const WalletScreen()),
                        );
                      },
                    ),
                    _menuTile(
                      icon: Icons.account_balance_outlined,
                      title: 'Withdraw',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DriverWithdrawScreen(),
                          ),
                        );
                      },
                    ),
                    _menuTile(
                      icon: Icons.star,
                      title: 'My Reviews',
                      iconColor: Colors.green,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DriverReviewsScreen(),
                          ),
                        );
                      },
                    ),
                    _menuTile(
                      icon: Icons.history_outlined,
                      title: 'Expiry & Penalty',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ExpiryHistoryScreen(),
                          ),
                        );
                      },
                    ),
                    _menuTile(
                      icon: Icons.settings_outlined,
                      title: 'App Settings',
                      onTap: () {
                        Navigator.pushNamed(context, '/app-settings');
                      },
                      showDivider: false,
                    ),
                  ],
                ),

                _menuCard(
                  children: [
                    buildToggle('Ride', isRideOn, (val) {
                      _onToggleChanged('ride', val);
                    }),
                    Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                    buildToggle('Parcel', isParcelOn, (val) {
                      _onToggleChanged('parcel', val);
                    }),
                    Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                    buildToggle('Intercity', isIntercityOn, (val) {
                      _onToggleChanged('intercity', val);
                    }),
                  ],
                ),

                _sectionTitle('Registration Details'),
                _menuCard(
                  children: [
                    _menuTile(
                      icon: Icons.badge_outlined,
                      title: 'Document Registration',
                      trailing: Consumer<DriverStatusSummaryProvider>(
                        builder: (context, s, _) {
                          return _statusIcon(s.summary.documentStatus);
                        },
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DocumentVerificationMenuScreen(),
                          ),
                        );
                      },
                    ),
                    _menuTile(
                      icon: Icons.directions_car_outlined,
                      title: 'Vehicle Registration',
                      trailing: Consumer<DriverStatusSummaryProvider>(
                        builder: (context, s, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _statusIcon(s.summary.vehicleStatus),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black26),
                            ],
                          );
                        },
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const VehicleRegistrationScreen(),
                          ),
                        ).then((_) {
                          if (!context.mounted) return;
                          context.read<DriverStatusSummaryProvider>().refresh(silent: true);
                        });
                      },
                    ),
                    _menuTile(
                      icon: Icons.account_balance_outlined,
                      title: 'Bank Details',
                      trailing: Consumer<DriverStatusSummaryProvider>(
                        builder: (context, s, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _statusIcon(s.summary.bankStatus),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black26),
                            ],
                          );
                        },
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BankDetailsScreen(),
                          ),
                        ).then((_) {
                          if (!context.mounted) return;
                          context.read<DriverStatusSummaryProvider>().refresh(silent: true);
                        });
                      },
                      showDivider: false,
                    ),
                  ],
                ),

                _sectionTitle('Alert Zone'),
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.red.shade100,
                        child: Icon(Icons.delete_outline, color: Colors.red.shade700, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Delete Account',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red.shade200),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Center(
                  child: InkWell(
                    onTap: () => showLogoutDialog(context),
                    child: const Text(
                      'Logout',
                      style: TextStyle(
                        color: Color(0xFF369D01),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Version: 2.0.3',
                    style: TextStyle(
                      color: Colors.black45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppShortcutsSheet extends StatelessWidget {
  const AppShortcutsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Your favorites',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Image.asset(
              'assets/images/no_favorites.png',
              height: 120,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.favorite_border,
                  size: 90,
                  color: Colors.grey.shade300,
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              "You don't have any favorites yet!",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Save a favorite first to add it to your home\nscreen for faster rides!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 18),
          ],
        ),
      ),
    );
  }
}

