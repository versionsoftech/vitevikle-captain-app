import 'package:flutter/material.dart';

class PassbookTransaction {
  final String title;
  final String amount;
  final String date;

  const PassbookTransaction({
    required this.title,
    required this.amount,
    required this.date,
  });
}

class PassbookScreen extends StatelessWidget {
  const PassbookScreen({super.key});

  Widget _helpButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.help_outline, size: 18),
        label: const Text('Help'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/payments/passbook_empty.png',
            width: 200,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.receipt_long,
                size: 96,
                color: Colors.grey.shade300,
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            "You don’t have any transactions yet!",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _transactionsList(List<PassbookTransaction> txns) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: txns.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey.shade200,
      ),
      itemBuilder: (context, index) {
        final t = txns[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(Icons.receipt, color: Colors.grey.shade700),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.amount,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                t.date,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<PassbookTransaction> transactions = const [];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Passbook'),
        actions: [_helpButton(context)],
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: transactions.isEmpty ? _emptyState(context) : _transactionsList(transactions),
    );
  }
}
