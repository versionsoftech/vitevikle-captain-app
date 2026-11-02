import 'package:flutter/material.dart';

class MyRatingScreen extends StatelessWidget {
  const MyRatingScreen({super.key});

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1E4D9B),
      ),
    );
  }

  Widget _sectionBody(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: Colors.grey.shade700,
      ),
    );
  }

  Widget _infoBlock(BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey.shade200,
            child: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFF4F7FF), Color(0xFFFFFFFF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 20,
            top: 22,
            child: Icon(Icons.star, color: Colors.orange.shade300, size: 22),
          ),
          Positioned(
            left: 58,
            top: 56,
            child: Icon(Icons.star, color: Colors.orange.shade200, size: 14),
          ),
          Positioned(
            right: 30,
            top: 20,
            child: Icon(Icons.star, color: Colors.orange.shade300, size: 28),
          ),
          Positioned(
            right: 80,
            top: 65,
            child: Icon(Icons.star, color: Colors.orange.shade200, size: 16),
          ),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star, color: Colors.orange.shade400, size: 30),
                const SizedBox(width: 8),
                Text(
                  '5.0',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Rating'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _banner(context),
              const SizedBox(height: 20),
              _sectionTitle('How is your rating calculated?'),
              const SizedBox(height: 8),
              _sectionBody(
                "Rating is calculated as an average of all your past ratings and is measured out of 5 stars. Ratings are 100% anonymous, so either you or your captain will never see rating for an individual ride.",
              ),
              const SizedBox(height: 20),
              _sectionTitle('Understanding Ratings'),
              const SizedBox(height: 8),
              _sectionBody(
                'To foster mutual respect Rapido captains and customers can rate each other on a scale of 1-5. Read on to understand how you can be a 5 star customer',
              ),
              const SizedBox(height: 20),
              _infoBlock(context, 
                icon: Icons.person_outline,
                title: 'Know your Captain',
                description:
                    "Knowing a little more about the things that affect a captain's happiness can help you be a 5-star rider.",
              ),
              _infoBlock(context, 
                icon: Icons.access_time,
                title: 'Timely',
                description:
                    'Check your pick up address and make sure that it is accurate. Reach the pickup spot on time. This helps the captain get you to your destination on time.',
              ),
              _infoBlock(context, 
                icon: Icons.verified_user_outlined,
                title: 'Safety',
                description:
                    'Sit back and relax. Every captain and customer should follow traffic rules and ensure a safe journey at all times.',
              ),
              _infoBlock(context, 
                icon: Icons.handshake_outlined,
                title: 'Courtesy',
                description:
                    'A smile or a “Hello” go a long way! Treat your captain just how you would like to be treated.',
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
