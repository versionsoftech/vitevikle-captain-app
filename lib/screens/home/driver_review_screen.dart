import 'package:flutter/material.dart';

class DriverReviewScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  final int rating;
  final String comment;

  const DriverReviewScreen({
    super.key,
    required this.ride,
    required this.rating,
    required this.comment,
  });

  @override
  State<DriverReviewScreen> createState() => _DriverReviewScreenState();
}

class _DriverReviewScreenState extends State<DriverReviewScreen> {
  static const Color primaryColor = Color(0xFF009640);

  @override
  Widget build(BuildContext context) {
    final riderName = (widget.ride['user_name'] ?? widget.ride['userName'] ?? widget.ride['name'] ?? 'Customer').toString().trim();

    final userImage = (widget.ride['user_image'] ?? widget.ride['userImage'] ?? widget.ride['profile_image'] ?? '').toString().trim();
    final hasUserImage = userImage.startsWith('http://') || userImage.startsWith('https://');

    final fareValue = widget.ride['fare'] ?? widget.ride['finalFare'] ?? widget.ride['amount'];
    final fare = fareValue is num ? fareValue.toDouble() : (double.tryParse(fareValue?.toString() ?? '') ?? 0);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          'Paid \u20B9${fare.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: primaryColor.withOpacity(0.12),
                      child: hasUserImage
                          ? ClipOval(
                              child: Image.network(
                                userImage,
                                width: 70,
                                height: 70,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(Icons.person, size: 36, color: Theme.of(context).colorScheme.onSurface);
                                },
                              ),
                            )
                          : Text(
                              riderName.isNotEmpty ? riderName[0].toUpperCase() : 'C',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                            ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'How was your ride with ${riderName.isEmpty ? 'Customer' : riderName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return Icon(
                          Icons.star,
                          size: 32,
                          color: index < widget.rating ? primaryColor : Colors.grey.shade300,
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.comment.trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          Navigator.popUntil(context, (route) => route.isFirst);
                        },
                        child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
