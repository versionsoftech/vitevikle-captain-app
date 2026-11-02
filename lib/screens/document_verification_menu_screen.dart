import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/providers/document_verification_provider.dart';
import 'package:vite_captain/screens/documents/aadhar_verification_screen.dart';
import 'package:vite_captain/screens/documents/dynamic_document_verification_screen.dart';
import 'package:vite_captain/screens/documents/pan_verification_screen.dart';
import 'package:vite_captain/screens/documents/license_verification_screen.dart';
import 'package:vite_captain/screens/documents/voter_verification_screen.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/widgets/curved_green_app_bar.dart';

class DocumentVerificationMenuScreen extends StatefulWidget {
  const DocumentVerificationMenuScreen({super.key});

  @override
  State<DocumentVerificationMenuScreen> createState() => _DocumentVerificationMenuScreenState();
}

class _DocumentVerificationMenuScreenState extends State<DocumentVerificationMenuScreen> {
  static const Color _primary = Color(0xFF369D01);
  static const Color _bg = Color(0xFFF6F7F9);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<DocumentVerificationProvider>();
      provider.hydrate();
      provider.loadConfigs();

      const SessionService().getDriverId().then((driverId) {
        final id = (driverId ?? '').trim();
        if (!mounted) return;
        if (id.isEmpty) return;
        provider.refreshServerStatuses(driverId: id);
      });
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Color _badgeColor(DocumentStatus status) {
    if (status == DocumentStatus.approved) return const Color(0xFF16A34A);
    if (status == DocumentStatus.rejected) return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  String _badgeText(DocumentStatus status) {
    if (status == DocumentStatus.approved) return 'Approved';
    if (status == DocumentStatus.rejected) return 'Rejected';
    return 'Pending';
  }

  Widget _menuCard({
    required IconData icon,
    required String title,
    required DocumentStatus status,
    required VoidCallback onTap,
  }) {
    final badgeBg = _badgeColor(status).withOpacity(0.12);
    final badgeFg = _badgeColor(status);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: _primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            SizedBox(
              width: 88,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _badgeText(status),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: badgeFg,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: curvedGreenAppBar(title: 'Document Registration'),
      body: SafeArea(
        child: Consumer<DocumentVerificationProvider>(
          builder: (context, docs, _) {
            final configs = docs.configs;
            final hasConfigs = configs.isNotEmpty;
            final allApproved = hasConfigs ? docs.isAllDocumentsApprovedFromServer : false;

            final sortedConfigs = [...configs];
            int rank(DocumentStatus s) {
              if (s == DocumentStatus.pending) return 0;
              if (s == DocumentStatus.rejected) return 1;
              return 2;
            }
            sortedConfigs.sort((a, b) {
              final sa = docs.getServerStatusForConfig(a);
              final sb = docs.getServerStatusForConfig(b);
              final ra = rank(sa);
              final rb = rank(sb);
              if (ra != rb) return ra.compareTo(rb);
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (docs.loadingConfigs) ...[
                  const SizedBox(height: 6),
                  const Center(child: ViteLoader()),
                  const SizedBox(height: 14),
                ],
                if (!docs.loadingConfigs && docs.configError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Text(
                      docs.configError!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (hasConfigs)
                  ...sortedConfigs.expand((c) {
                    final key = (c.key ?? '').toLowerCase().trim();

                    DocumentStatus status = docs.getServerStatusForConfig(c);
                    IconData icon = Icons.description_outlined;
                    VoidCallback onTap = () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DynamicDocumentVerificationScreen(config: c),
                        ),
                      );
                    };

                    if (key == 'aadhar') {
                      icon = Icons.credit_card;
                    } else if (key == 'pan') {
                      icon = Icons.badge_outlined;
                    } else if (key == 'license') {
                      icon = Icons.card_membership_outlined;
                    } else if (key == 'voter') {
                      icon = Icons.how_to_vote_outlined;
                    }

                    return <Widget>[
                      _menuCard(
                        icon: icon,
                        title: c.name,
                        status: status,
                        onTap: onTap,
                      ),
                      const SizedBox(height: 12),
                    ];
                  }).toList(),
                if (!hasConfigs) ...[
                  _menuCard(
                    icon: Icons.credit_card,
                    title: 'Aadhar Card',
                    status: docs.aadharStatus,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AadharVerificationScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _menuCard(
                    icon: Icons.badge_outlined,
                    title: 'PAN Card',
                    status: docs.panStatus,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PanVerificationScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _menuCard(
                    icon: Icons.card_membership_outlined,
                    title: 'Driver License',
                    status: docs.licenseStatus,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LicenseVerificationScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _menuCard(
                    icon: Icons.how_to_vote_outlined,
                    title: 'Voter Card',
                    status: docs.voterStatus,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const VoterVerificationScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: allApproved ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: allApproved ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        allApproved ? Icons.check_circle : Icons.info,
                        color: allApproved ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          allApproved
                              ? 'All documents are approved. You can go online.'
                              : 'Complete document verification to go online.',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

