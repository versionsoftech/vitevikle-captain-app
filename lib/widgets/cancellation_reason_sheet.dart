import 'package:flutter/material.dart';
import 'package:vite_captain/services/api_service.dart';

class CancellationReasonSheet {
  static Future<Map<String, String>?> show({
    required BuildContext context,
    required String type,
    String title = 'Cancel',
    String confirmText = 'Confirm Cancel',
    String? topMessage,
  }) async {
    final safeType = type.trim().toLowerCase();

    String selectedReasonId = '';
    String selectedReasonText = '';
    final noteCtrl = TextEditingController();
    bool isSubmitting = false;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final effectiveTop = (topMessage ?? '').trim().isNotEmpty
            ? topMessage!.trim()
            : 'Select a reason to continue.';

        return FractionallySizedBox(
          heightFactor: 0.9,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                return Column(
                  children: [
                    Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        effectiveTop,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Select a reason', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: const ApiService().getCancellationReasons(type: safeType),
                        builder: (ctx, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final payload = snap.data ?? <String, dynamic>{};
                          final ok = payload['success'] == true;
                          final list = payload['data'];
                          final reasons = (ok && list is List) ? list : <dynamic>[];

                          if (!ok) {
                            return Center(
                              child: Text(
                                (payload['message'] ?? 'Failed to load reasons').toString(),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }

                          if (reasons.isEmpty) {
                            return const Center(child: Text('No cancellation reasons available'));
                          }

                          return ListView.separated(
                            itemCount: reasons.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (ctx, i) {
                              final raw = reasons[i];
                              if (raw is! Map) return const SizedBox.shrink();
                              final m = Map<String, dynamic>.from(raw);
                              final id = (m['id'] ?? m['_id'] ?? '').toString().trim();
                              final text = (m['reason_text'] ?? m['reason'] ?? '').toString().trim();
                              final selected = id.isNotEmpty && id == selectedReasonId;

                              return InkWell(
                                onTap: () {
                                  if (id.isEmpty) return;
                                  setLocal(() {
                                    selectedReasonId = id;
                                    selectedReasonText = text;
                                  });
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                                      width: selected ? 1.6 : 1,
                                    ),
                                    color: selected ? const Color(0xFFF8FAFC) : Colors.white,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: selected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          selected ? Icons.check_rounded : Icons.info_outline_rounded,
                                          color: selected ? Colors.white : const Color(0xFF0F172A),
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          text.isEmpty ? '-' : text,
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      decoration: InputDecoration(
                        labelText: selectedReasonText.trim().toLowerCase() == 'other'
                            ? 'Tell us more (optional)'
                            : 'Add a note (optional)',
                        border: const OutlineInputBorder(),
                      ),
                      minLines: selectedReasonText.trim().toLowerCase() == 'other' ? 2 : 1,
                      maxLines: selectedReasonText.trim().toLowerCase() == 'other' ? 4 : 3,
                    ),
                    const SizedBox(height: 12),
                    SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              onPressed: (isSubmitting || selectedReasonId.isEmpty)
                                  ? null
                                  : () {
                                      Navigator.pop(ctx, {
                                        'cancellation_reason_id': selectedReasonId,
                                        'reason': selectedReasonText,
                                        'note': noteCtrl.text,
                                      });
                                    },
                              child: isSubmitting
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(confirmText),
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
      },
    );
    return result;
  }
}

