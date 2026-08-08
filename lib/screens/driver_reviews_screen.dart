import 'package:flutter/material.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:intl/intl.dart';

class DriverReviewsScreen extends StatelessWidget {
  static const Color primaryColor = Color(0xFF22C55E);

  const DriverReviewsScreen({super.key});

  Widget _skeletonCard() {
    Widget bar({required double w, required double h}) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 24, backgroundColor: Colors.grey.shade200),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(w: 140, h: 14),
                const SizedBox(height: 10),
                bar(w: 110, h: 12),
                const SizedBox(height: 12),
                bar(w: double.infinity, h: 12),
                const SizedBox(height: 8),
                bar(w: 200, h: 12),
                const SizedBox(height: 12),
                Row(
                  children: [
                    bar(w: 88, h: 26),
                    const SizedBox(width: 8),
                    bar(w: 76, h: 26),
                  ],
                ),
                const SizedBox(height: 12),
                bar(w: 150, h: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _formatDate(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    DateTime? dt;
    try {
      dt = DateTime.parse(s).toLocal();
    } catch (_) {
      final epoch = int.tryParse(s);
      if (epoch != null && epoch > 0) {
        dt = DateTime.fromMillisecondsSinceEpoch(
          epoch.toString().length == 10 ? epoch * 1000 : epoch,
        ).toLocal();
      }
    }
    if (dt == null) return s;
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('My Reviews'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              primaryColor.withOpacity(0.08),
            ],
          ),
        ),
        child: FutureBuilder<String?>(
          future: const SessionService().getDriverId(),
          builder: (context, driverSnap) {
            final driverId = (driverSnap.data ?? '').trim();
            if (driverSnap.connectionState != ConnectionState.done) {
              return ListView(
                physics: const BouncingScrollPhysics(),
                children: List.generate(6, (_) => _skeletonCard()),
              );
            }
            if (driverId.isEmpty) {
              return const Center(child: Text('No reviews yet'));
            }

            return FutureBuilder<Map<String, dynamic>>(
              future: const ApiService().getDriverReviews(driverId: driverId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return ListView(
                    physics: const BouncingScrollPhysics(),
                    children: List.generate(6, (_) => _skeletonCard()),
                  );
                }

                final res = snapshot.data ?? const <String, dynamic>{};
                final ok = res['success'] == true;
                final list = ok && res['data'] is List ? (res['data'] as List) : const <dynamic>[];

                if (list.isEmpty) {
                  return const Center(child: Text('No reviews yet'));
                }

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(top: 10, bottom: 16),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final item = list[index];
                    final review = item is Map ? Map<String, dynamic>.from(item) : const <String, dynamic>{};

                    // Try to get customer name from populated rider_id or rider_name field
                    final riderData = review['rider_id'] is Map ? review['rider_id'] as Map<String, dynamic> : null;
                    final name = (review['rider_name'] ?? riderData?['name'] ?? riderData?['fullName'] ?? review['user_name'] ?? 'User').toString().trim();
                    final imageUrl = (review['rider_image'] ?? riderData?['profileImage'] ?? riderData?['image'] ?? riderData?['user_image'] ?? review['user_image'] ?? '').toString().trim();
                    final hasImage = imageUrl.isNotEmpty;
                    
                    print('[REVIEWS] Review ID: ${review['_id']}');
                    print('[REVIEWS] Rider Name: $name');
                    print('[REVIEWS] Rider Image: $imageUrl');
                    print('[REVIEWS] Has Image: $hasImage');

                    final rating = _asInt(review['rating']);
                    final message = (review['comment'] ?? '').toString().trim();
                    final tags = review['tags'] is List ? List<String>.from(review['tags'] as List) : <String>[];
                    final dateText = _formatDate(review['created_at']);

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: primaryColor.withOpacity(0.12),
                                backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
                                child: !hasImage
                                    ? Text(
                                        (name.isNotEmpty ? name[0] : 'U').toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isEmpty ? 'User' : name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: List.generate(5, (i) {
                                        return Icon(
                                          i < rating ? Icons.star : Icons.star_border,
                                          color: primaryColor,
                                          size: 18,
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (message.isNotEmpty)
                            Text(
                              message,
                              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                            ),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: tags.map<Widget>((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(color: primaryColor, fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                          if (dateText.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              dateText,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

