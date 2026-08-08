import 'package:flutter/material.dart';

class ClaimsScreen extends StatelessWidget {
  const ClaimsScreen({super.key});

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF2F5E8C),
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _coverageRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: Colors.black87),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legalRow({
    required String title,
    required VoidCallback onView,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: onView,
            child: const Text(
              'View',
              style: TextStyle(
                color: Color(0xFF2F6FD6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Claims',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.grey.shade100,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text('Help'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              onPressed: () {},
              child: const Text(
                'Claim Insurance',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEF9A9A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info, color: Color(0xFFD32F2F), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Update missing profile details to claim your insurance',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle('POLICY COVERAGE'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _coverageRow(
                    icon: Icons.personal_injury_outlined,
                    title: 'Personal Accident/Accidental Death',
                    subtitle: 'Up to ₹5,00,000',
                  ),
                  Divider(height: 1, thickness: 0.6, color: Colors.grey.shade200),
                  _coverageRow(
                    icon: Icons.local_hospital_outlined,
                    title: 'Medical Expense for Hospitalization',
                    subtitle: 'Up to ₹1,00,000',
                  ),
                  Divider(height: 1, thickness: 0.6, color: Colors.grey.shade200),
                  _coverageRow(
                    icon: Icons.medical_services_outlined,
                    title: 'OPD Treatment',
                    subtitle: 'Up to ₹3000',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('LEGAL'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _legalRow(title: 'Claim Procedure', onView: () {}),
                  Divider(height: 1, thickness: 0.6, color: Colors.grey.shade200),
                  _legalRow(title: 'Terms and Conditions', onView: () {}),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Please provide your correct email-id, date of birth and phone number to avoid cancellations of your insurance claim.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Powered by Acko',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
