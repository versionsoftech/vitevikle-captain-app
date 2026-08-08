import 'package:flutter/material.dart';

class ServiceCategoryCard extends StatelessWidget {
  final String title;
  final String iconUrl;
  final bool selected;
  final VoidCallback? onTap;
  final double? width;

  const ServiceCategoryCard({
    super.key,
    required this.title,
    required this.iconUrl,
    required this.selected,
    this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cardWidth = (width ?? 86).clamp(54, 86).toDouble();
    final scale = (cardWidth / 86).clamp(0.63, 1.0);
    final hPad = (10 * scale).clamp(6, 10).toDouble();
    final vPad = (8 * scale).clamp(6, 8).toDouble();
    final iconWidth = (64 * scale).clamp(44, 64).toDouble();
    final fontSize = (12 * scale).clamp(10, 12).toDouble();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: cardWidth,
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF2F6BFF) : Colors.transparent,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: iconWidth,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: iconUrl.trim().isEmpty
                    ? const ColoredBox(color: Color(0xFFE5E7EB))
                    : Image.network(
                        iconUrl,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: Color(0xFFE5E7EB)),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
