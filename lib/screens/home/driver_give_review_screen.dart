import 'package:flutter/material.dart';
import 'package:vite_captain/screens/home_screen.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';

class DriverGiveReviewScreen extends StatefulWidget {
  final String rideId;
  final String userId;
  final String userName;
  final String userImageUrl;
  final double paidAmount;
  final String? reviewType;

  const DriverGiveReviewScreen({
    super.key,
    required this.rideId,
    required this.userId,
    required this.userName,
    required this.userImageUrl,
    required this.paidAmount,
    this.reviewType,
  });

  @override
  State<DriverGiveReviewScreen> createState() => _DriverGiveReviewScreenState();
}

class _DriverGiveReviewScreenState extends State<DriverGiveReviewScreen> {
  static const Color primaryColor = Color(0xFF22C55E);

  int rating = 0;
  String reviewText = '';
  final Set<String> _selectedTags = <String>{};
  bool _submitting = false;

  String? _fetchedUserName;
  String? _fetchedUserImage;

  bool get _hasUserImage {
    final url = _resolvedUserImageUrl.trim();
    return url.startsWith('http://') || url.startsWith('https://');
  }

  String get _resolvedUserName {
    final fromApi = (_fetchedUserName ?? '').trim();
    if (fromApi.isNotEmpty) return fromApi;
    final fromNav = widget.userName.trim();
    if (fromNav.isNotEmpty) return fromNav;
    return '';
  }

  String get _resolvedUserImageUrl {
    final fromApi = (_fetchedUserImage ?? '').trim();
    if (fromApi.isNotEmpty) {
      final lower = fromApi.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) return fromApi;
      final root = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
      if (fromApi.startsWith('/')) return '$root$fromApi';
      if (fromApi.startsWith('uploads/')) return '$root/$fromApi';
      return '$root/uploads/$fromApi';
    }

    final fromNav = widget.userImageUrl.trim();
    return fromNav;
  }

  Future<void> _fetchUser() async {
    final userId = widget.userId.trim();
    if (userId.isEmpty) return;
    try {
      final res = await const ApiService().getUserById(userId: userId);
      debugPrint('USER API RESPONSE: ${res.toString()}');
      if (!mounted) return;
      if (res['success'] == true && res['user'] is Map) {
        final u = Map<String, dynamic>.from(res['user'] as Map);
        final name = (u['name'] ?? '').toString().trim();
        final image = (u['image'] ?? '').toString().trim();
        if (name.isEmpty && image.isEmpty) return;
        setState(() {
          _fetchedUserName = name;
          _fetchedUserImage = image;
        });
      }
    } catch (_) {
      debugPrint('USER FETCH ERROR');
      return;
    }
  }

  Widget chip(String text) {
    final selected = _selectedTags.contains(text);
    return InkWell(
      onTap: () {
        setState(() {
          if (selected) {
            _selectedTags.remove(text);
          } else {
            _selectedTags.add(text);
          }
        });
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primaryColor.withOpacity(0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? primaryColor : Colors.transparent),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? primaryColor : Colors.black87,
          ),
        ),
      ),
    );
  }

  Future<void> _goHome() async {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _showSubmitSuccessAndGoHome() async {
    if (!mounted) return;
    final screenContext = context;

    showDialog(
      context: screenContext,
      barrierDismissible: false,
      builder: (context) {
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
          if (Navigator.canPop(screenContext)) {
            Navigator.of(screenContext).pop(true);
          }
        });

        return Material(
          color: Colors.transparent,
          child: Dialog(
            backgroundColor: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 72,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Review Submitted",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Thank you for sharing your feedback.",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.of(context).pop();
                        }
                        if (Navigator.canPop(screenContext)) {
                          Navigator.of(screenContext).pop(true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Done",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit({required bool skip}) async {
    if (_submitting) return;

    if (!skip && rating == 0) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Please select rating')));
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      if (!skip) {
        final parts = <String>[];
        if (_selectedTags.isNotEmpty) parts.addAll(_selectedTags);
        final freeText = reviewText.trim();
        if (freeText.isNotEmpty) parts.add(freeText);
        final comment = parts.join(parts.length > 1 ? ' • ' : '');

        final reviewerId = (await const SessionService().getDriverId())?.trim() ?? '';

        debugPrint({
          'ride_id': widget.rideId,
          'user_id': widget.userId,
          'driver_id': reviewerId,
          'rating': rating,
        }.toString());

        final resp = await const ApiService().submitReview(
          rideId: widget.rideId,
          reviewerId: reviewerId,
          reviewFor: widget.userId,
          rating: rating,
          tags: _selectedTags.toList(),
          comment: comment,
          type: (widget.reviewType ?? 'driver_to_user').trim(),
        );

        final ok = resp['status'] == true || resp['success'] == true;
        if (!ok) {
          if (!mounted) return;
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(const SnackBar(content: Text('Unable to submit review. Try again')));
          return;
        }
      } else {
        await _goHome();
        return;
      }
    } catch (_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Unable to submit review. Try again')));
      return;
    }

    if (!mounted) return;
    await _showSubmitSuccessAndGoHome();
  }

  @override
  void initState() {
    super.initState();
    _fetchUser();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _resolvedUserName.isEmpty ? 'Customer' : _resolvedUserName;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Rate User'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: primaryColor),
                      const SizedBox(width: 6),
                      Text(
                        'Paid ₹${widget.paidAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  TextButton(onPressed: () {}, child: const Text('Help')),
                ],
              ),
              const SizedBox(height: 30),
              CircleAvatar(
                radius: 40,
                backgroundColor: primaryColor.withOpacity(0.12),
                backgroundImage: _hasUserImage ? NetworkImage(_resolvedUserImageUrl) : null,
                child: !_hasUserImage ? const Icon(Icons.person, size: 42, color: Colors.black87) : null,
              ),
              const SizedBox(height: 20),
              Text(
                'How was your ride with $displayName',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final filled = index < rating;
                  return IconButton(
                    icon: Icon(Icons.star, size: 35, color: filled ? primaryColor : Colors.grey.shade300),
                    onPressed: () {
                      setState(() {
                        rating = index + 1;
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 10),
              Text(
                'Great, what did you like the most?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  chip('Comfortable ride'),
                  chip('Professional'),
                  chip('Affordable'),
                  chip('Clean'),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                enableInteractiveSelection: false,
                decoration: InputDecoration(
                  hintText: 'Tell us more...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: primaryColor, width: 1.4),
                  ),
                ),
                onChanged: (val) {
                  reviewText = val;
                },
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _submitting ? null : () async => _submit(skip: false),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _submitting ? null : () async => _submit(skip: true),
                  child: const Text('Skip', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

