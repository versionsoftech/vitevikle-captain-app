import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:dio/dio.dart';

class ExpiryHistoryScreen extends StatefulWidget {
  const ExpiryHistoryScreen({super.key});

  @override
  State<ExpiryHistoryScreen> createState() => _ExpiryHistoryScreenState();
}

class _ExpiryHistoryScreenState extends State<ExpiryHistoryScreen> {
  late Future<Map<String, dynamic>> _expiryHistoryFuture;
  bool _isLoading = false;

  // Filter state
  String _rideTypeFilter = 'All';
  String _penaltyFilter = 'All';
  String _dateFilter = 'All';
  String _sortFilter = 'Newest First';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _expiryHistoryFuture = _fetchExpiryHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchExpiryHistory() async {
    try {
      print('Loading expiry history...');
      final token = (await const SessionService().getToken() ?? '').trim();
      if (token.isEmpty) {
        print('Authentication failed: No token');
        return {
          'success': false,
          'message': 'Authentication failed',
          'data': {'expiry_count': 0, 'expiry_history': [], 'account_review_required': false}
        };
      }

      print('Token found, making API call to /api/v1/driver/expiry-history');
      final response = await DioClient.dio.get(
        '/api/v1/driver/expiry-history',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      print('API response received: ${response.data}');
      
      if (response.data is Map && response.data['success'] == true) {
        // Check if response has new format or old format
        if (response.data.containsKey('total_expired_documents')) {
          // New format
          print('Using new response format');
          return response.data as Map<String, dynamic>;
        } else if (response.data.containsKey('data')) {
          // Old format
          print('Using old response format');
          final data = response.data['data'];
          final expiryCount = data?['expiry_count'] ?? 0;
          final expiryHistory = data?['expiry_history'] as List<dynamic>? ?? [];
          print('Records found: $expiryCount, History length: ${expiryHistory.length}');
          return response.data as Map<String, dynamic>;
        }
      }

      print('API returned success=false or invalid format');
      return {
        'success': false,
        'message': response.data['message'] ?? 'Failed to load expiry history',
        'data': {'expiry_count': 0, 'expiry_history': [], 'account_review_required': false}
      };
    } catch (e, stackTrace) {
      print('Error loading expiry history: $e');
      print('Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Error loading expiry history: ${e.toString()}',
        'data': {'expiry_count': 0, 'expiry_history': [], 'account_review_required': false}
      };
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final dateTime = date is DateTime ? date : DateTime.parse(date.toString());
      return DateFormat('dd-MMM-yyyy').format(dateTime);
    } catch (_) {
      return '-';
    }
  }

  String _getExpiryNumberText(int expiryCount) {
    if (expiryCount == 1) return '1st Expiry';
    if (expiryCount == 2) return '2nd Expiry';
    if (expiryCount == 3) return '3rd Expiry';
    return '${expiryCount}th Expiry';
  }

  String _getPenaltyText(dynamic penaltyPercent, dynamic penaltyAmount) {
    if (penaltyPercent == 0 || penaltyPercent == null) {
      return 'Warning';
    }
    final percent = penaltyPercent.toInt();
    final amount = penaltyAmount?.toInt() ?? 0;
    return '$percent% (₹$amount)';
  }

  Color _getPenaltyColor(int penaltyPercentage) {
    if (penaltyPercentage == 0) return Colors.orange;
    if (penaltyPercentage == 10) return Colors.blue;
    if (penaltyPercentage == 25) return Colors.indigo;
    if (penaltyPercentage == 40) return Colors.purple;
    if (penaltyPercentage == 60) return Colors.red;
    return Colors.red;
  }

  String _getPenaltyLevelText(int penaltyPercentage) {
    if (penaltyPercentage == 0) return 'Warning';
    if (penaltyPercentage == 10) return '10%';
    if (penaltyPercentage == 25) return '25%';
    if (penaltyPercentage == 40) return '40%';
    if (penaltyPercentage == 60) return '60%';
    return 'Under Review';
  }

  Widget _buildRiskProgressBar(int expiredCount) {
    String riskLevel = 'Low Risk';
    Color riskColor = Colors.green;
    double progress = 0.0;

    if (expiredCount >= 0 && expiredCount <= 4) {
      riskLevel = 'Low Risk';
      riskColor = Colors.green;
      progress = expiredCount / 4;
    } else if (expiredCount >= 5 && expiredCount <= 7) {
      riskLevel = 'Medium Risk';
      riskColor = Colors.orange;
      progress = (expiredCount - 4) / 3;
    } else if (expiredCount >= 8 && expiredCount <= 9) {
      riskLevel = 'High Risk';
      riskColor = Colors.red;
      progress = (expiredCount - 7) / 2;
    } else if (expiredCount >= 10) {
      riskLevel = 'Under Review';
      riskColor = Colors.red.shade900;
      progress = 1.0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation<Color>(riskColor),
          minHeight: 4,
        ),
        const SizedBox(height: 4),
        Text(
          riskLevel,
          style: TextStyle(
            fontSize: 10,
            color: riskColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required Color valueColor,
    required String subtitle,
    bool showRiskBar = false,
    int expiredCount = 0,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
              ),
            ),
            if (showRiskBar) ...[
              const SizedBox(height: 8),
              _buildRiskProgressBar(expiredCount),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, List<String> options, String selectedValue, Function(String) onSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: options.map((option) {
            final isSelected = selectedValue == option;
            return FilterChip(
              label: Text(
                option,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.white : Colors.grey[700],
                ),
              ),
              selected: isSelected,
              onSelected: (bool selected) {
                if (selected) {
                  onSelected(option);
                }
              },
              selectedColor: const Color(0xFF369D01),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: isSelected ? const Color(0xFF369D01) : Colors.grey.shade300,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filter',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Ride Type', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['All', 'Parcel Ride', 'Intercity Ride'].map((option) {
                final isSelected = _rideTypeFilter == option;
                return FilterChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() => _rideTypeFilter = option);
                    }
                  },
                  selectedColor: const Color(0xFF369D01),
                  backgroundColor: Colors.grey.shade100,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Penalty Level', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['All', 'Warning', '10%', '25%', '40%', '60%', 'Under Review'].map((option) {
                final isSelected = _penaltyFilter == option;
                return FilterChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() => _penaltyFilter = option);
                    }
                  },
                  selectedColor: const Color(0xFF369D01),
                  backgroundColor: Colors.grey.shade100,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Date Range', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['All', 'Today', 'Last 7 Days', 'Last 30 Days', 'This Month'].map((option) {
                final isSelected = _dateFilter == option;
                return FilterChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() => _dateFilter = option);
                    }
                  },
                  selectedColor: const Color(0xFF369D01),
                  backgroundColor: Colors.grey.shade100,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _rideTypeFilter = 'All';
                        _penaltyFilter = 'All';
                        _dateFilter = 'All';
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF369D01),
                    ),
                    child: const Text('Apply Filter'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSortBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sort',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...['Newest First', 'Oldest First', 'Highest Penalty', 'Lowest Penalty'].map((option) {
              final isSelected = _sortFilter == option;
              return ListTile(
                title: Text(option),
                trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF369D01)) : null,
                onTap: () {
                  setState(() => _sortFilter = option);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredDocuments(List<dynamic> expiredDocuments) {
    List<Map<String, dynamic>> filtered = expiredDocuments
        .where((doc) => doc != null && doc is Map)
        .map((doc) => doc as Map<String, dynamic>)
        .toList();

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((doc) {
        final documentName = (doc['document_name'] ?? '').toString().toLowerCase();
        return documentName.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Apply ride type filter
    if (_rideTypeFilter != 'All') {
      filtered = filtered.where((doc) {
        final documentName = (doc['document_name'] ?? '').toString().toLowerCase();
        if (_rideTypeFilter == 'Parcel Ride') {
          return documentName.contains('parcel');
        } else if (_rideTypeFilter == 'Intercity Ride') {
          return documentName.contains('intercity');
        }
        return true;
      }).toList();
    }

    // Apply penalty filter
    if (_penaltyFilter != 'All') {
      filtered = filtered.where((doc) {
        final penaltyStatus = (doc['penalty_status'] ?? '').toString();
        final penaltyPercentage = doc['penalty_percentage'] ?? 0;
        
        if (_penaltyFilter == 'Warning') {
          return penaltyPercentage == 0;
        } else if (_penaltyFilter == '10%') {
          return penaltyPercentage == 10;
        } else if (_penaltyFilter == '25%') {
          return penaltyPercentage == 25;
        } else if (_penaltyFilter == '40%') {
          return penaltyPercentage == 40;
        } else if (_penaltyFilter == '60%') {
          return penaltyPercentage == 60;
        } else if (_penaltyFilter == 'Under Review') {
          return penaltyPercentage >= 60;
        }
        return true;
      }).toList();
    }

    // Apply date filter
    if (_dateFilter != 'All') {
      final now = DateTime.now();
      filtered = filtered.where((doc) {
        final expiryDateStr = doc['expiry_date'] ?? '';
        if (expiryDateStr == null || expiryDateStr == '') return false;
        
        try {
          final expiryDate = DateTime.parse(expiryDateStr.toString());
          
          if (_dateFilter == 'Today') {
            return expiryDate.year == now.year &&
                   expiryDate.month == now.month &&
                   expiryDate.day == now.day;
          } else if (_dateFilter == 'Last 7 Days') {
            return expiryDate.isAfter(now.subtract(const Duration(days: 7)));
          } else if (_dateFilter == 'Last 30 Days') {
            return expiryDate.isAfter(now.subtract(const Duration(days: 30)));
          } else if (_dateFilter == 'This Month') {
            return expiryDate.year == now.year && expiryDate.month == now.month;
          }
        } catch (e) {
          return false;
        }
        return true;
      }).toList();
    }

    // Apply sort
    switch (_sortFilter) {
      case 'Newest First':
        filtered.sort((a, b) {
          final dateA = DateTime.tryParse(a['expiry_date']?.toString() ?? '') ?? DateTime(0);
          final dateB = DateTime.tryParse(b['expiry_date']?.toString() ?? '') ?? DateTime(0);
          return dateB.compareTo(dateA);
        });
        break;
      case 'Oldest First':
        filtered.sort((a, b) {
          final dateA = DateTime.tryParse(a['expiry_date']?.toString() ?? '') ?? DateTime(0);
          final dateB = DateTime.tryParse(b['expiry_date']?.toString() ?? '') ?? DateTime(0);
          return dateA.compareTo(dateB);
        });
        break;
      case 'Highest Penalty':
        filtered.sort((a, b) {
          final penaltyA = (a['penalty_percentage'] ?? 0) as int;
          final penaltyB = (b['penalty_percentage'] ?? 0) as int;
          return penaltyB.compareTo(penaltyA);
        });
        break;
      case 'Lowest Penalty':
        filtered.sort((a, b) {
          final penaltyA = (a['penalty_percentage'] ?? 0) as int;
          final penaltyB = (b['penalty_percentage'] ?? 0) as int;
          return penaltyA.compareTo(penaltyB);
        });
        break;
    }

    return filtered;
  }

  int _calculatePenaltyAmount(Map<String, dynamic> docMap) {
    // Read actual penalty amount from backend API response
    // The backend now sends penalty_amount field from driver_transactions
    final penaltyAmount = docMap['penalty_amount'] ?? 0;
    final amountValue = (penaltyAmount is num) ? penaltyAmount.toInt() : 
                       (penaltyAmount is String) ? int.tryParse(penaltyAmount) ?? 0 : 0;
    
    print('[EXPIRY] Ride ID: ${docMap['ride_id']}');
    print('[EXPIRY] Penalty %: ${docMap['penalty_percentage']}');
    print('[EXPIRY] Penalty Amount from API: $penaltyAmount');
    print('[EXPIRY] Calculated Amount: $amountValue');
    
    return amountValue;
  }

  void _showRideDetailsBottomSheet(Map<String, dynamic> docMap) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Ride Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildDetailRow('Ride Type', docMap['ride_type']?.toString() == 'parcel' ? 'Parcel Ride' : 'Intercity Ride'),
                    _buildDetailRow('Ride ID', docMap['ride_id']?.toString() ?? docMap['document_name']?.toString().split(' - ').last ?? 'Unknown'),
                    _buildDetailRow('Booking Date', _formatDate(docMap['created_at'])),
                    _buildDetailRow('Pickup Date', docMap['pickup_date']?.toString() ?? 'N/A'),
                    _buildDetailRow('Pickup Time', docMap['pickup_time']?.toString() ?? 'N/A'),
                    _buildDetailRow('Expired Date', _formatDate(docMap['cancelled_at'])),
                    _buildDetailRow('Ride Fare', '₹${docMap['ride_amount'] ?? '0'}'),
                    _buildDetailRow('Penalty Percentage', docMap['penalty']?.toString() ?? '0%'),
                    _buildDetailRow('Penalty Amount', '₹${_calculatePenaltyAmount(docMap)}'),
                    _buildDetailRow('Wallet Deducted', '₹${_calculatePenaltyAmount(docMap)}'),
                    _buildDetailRow('Deduction Date', _formatDate(docMap['cancelled_at'])),
                    _buildDetailRow('Status', docMap['status']?.toString() ?? 'Expired'),
                    _buildDetailRow('Account Status', 'Active'),
                    const SizedBox(height: 16),
                    const Text(
                      'Cancellation Reason',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        docMap['cancellation_reason']?.toString() ?? 'Driver No Show - Pickup not started within grace period',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Timeline Section
                    const Text(
                      'Timeline',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTimelineItem('Ride Created', _formatDate(docMap['created_at']), Icons.add_circle_outline),
                    _buildTimelineItem('Ride Accepted', '-', Icons.check_circle_outline),
                    _buildTimelineItem('Ride Expired', _formatDate(docMap['cancelled_at']), Icons.warning_amber_rounded, Colors.orange),
                    _buildTimelineItem('Penalty Applied', _formatDate(docMap['cancelled_at']), Icons.gavel, Colors.red),
                    _buildTimelineItem('Wallet Deducted', _formatDate(docMap['cancelled_at']), Icons.account_balance_wallet, Colors.red),
                    const SizedBox(height: 24),
                    // Close Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF369D01),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(String title, String date, IconData icon, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (color ?? Colors.grey).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color ?? Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Expiry & Penalty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Track expired rides and penalties',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF369D01),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              // Show help dialog
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Expiry & Penalty Help'),
                  content: const Text(
                    'This screen shows your expired rides and associated penalties. Continued ride expiry may result in increased penalties and account review.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _expiryHistoryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading expiry history',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _expiryHistoryFuture = _fetchExpiryHistory();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data;
          final success = data?['success'] == true;
          
          // Check if response is new format or old format
          final isNewFormat = data?.containsKey('total_expired_documents') == true;
          
          // New format fields
          final totalExpiredDocuments = data?['total_expired_documents'] ?? 0;
          final penaltyPercentage = data?['penalty_percentage'] ?? 0;
          final walletDeducted = data?['wallet_deducted'] ?? 0;
          final walletBalance = data?['wallet_balance'] ?? 0;
          final expiredDocuments = data?['expired_documents'] as List<dynamic>? ?? [];
          final penaltyHistory = data?['penalty_history'] as List<dynamic>? ?? [];
          
          // Old format fields (for backward compatibility)
          final expiryData = data?['data'] as Map<String, dynamic>?;
          final expiryCount = expiryData?['expiry_count'] ?? 0;
          final expiryHistory = expiryData?['expiry_history'] as List<dynamic>? ?? [];
          final accountReviewRequired = expiryData?['account_review_required'] ?? false;

          if (!success) {
            final errorMessage = data?['message'] ?? 'Failed to load expiry history';
            print('Showing error screen: $errorMessage');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage,
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _expiryHistoryFuture = _fetchExpiryHistory();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _expiryHistoryFuture = _fetchExpiryHistory();
              });
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Alert Card - Show only when expired rides > 0
                  if (isNewFormat && totalExpiredDocuments > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.shade100.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.amber.shade800,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Expired rides detected. Continued ride expiry may result in penalties and account review.',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Account Review Warning Banner (Old format)
                  if (!isNewFormat && accountReviewRequired)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your account is under review due to repeated ride expiries.',
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Overview Section
                  if (isNewFormat)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Use a more flexible layout instead of GridView to avoid overflow
                        Column(
                          children: [
                            // Row 1: Cards 1 and 2
                            Row(
                              children: [
                                Expanded(
                                  child: _buildSummaryCard(
                                    icon: Icons.description,
                                    iconColor: const Color(0xFF369D01),
                                    title: 'Total Expired Rides',
                                    value: '$totalExpiredDocuments',
                                    valueColor: const Color(0xFF369D01),
                                    subtitle: 'Expired Records',
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildSummaryCard(
                                    icon: Icons.warning,
                                    iconColor: _getPenaltyColor(penaltyPercentage),
                                    title: 'Current Penalty Level',
                                    value: _getPenaltyLevelText(penaltyPercentage),
                                    valueColor: _getPenaltyColor(penaltyPercentage),
                                    subtitle: 'Risk Level',
                                    showRiskBar: true,
                                    expiredCount: totalExpiredDocuments,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Row 2: Cards 3 and 4
                            Row(
                              children: [
                                Expanded(
                                  child: _buildSummaryCard(
                                    icon: Icons.account_balance_wallet,
                                    iconColor: Colors.red,
                                    title: 'Total Penalty Deducted',
                                    value: '₹$walletDeducted',
                                    valueColor: Colors.red,
                                    subtitle: 'Lifetime Deduction',
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildSummaryCard(
                                    icon: Icons.wallet,
                                    iconColor: const Color(0xFF369D01),
                                    title: 'Wallet Balance',
                                    value: '₹$walletBalance',
                                    valueColor: const Color(0xFF369D01),
                                    subtitle: 'Available Balance',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Expiries',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$expiryCount',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF369D01),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Compact Filter Section
                  if (isNewFormat && expiredDocuments.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search Ride ID',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: () {
                                        setState(() {
                                          _searchController.clear();
                                          _searchQuery = '';
                                        });
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              isDense: true,
                            ),
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.filter_list, size: 20),
                            onPressed: () => _showFilterBottomSheet(),
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.sort, size: 20),
                            onPressed: () => _showSortBottomSheet(),
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 16),

                  // Expired Documents List (New Format)
                  if (isNewFormat && expiredDocuments.isNotEmpty) ...[
                    Text(
                      'Expired Rides',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _getFilteredDocuments(expiredDocuments).length,
                      separatorBuilder: (context, index) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final filteredDocs = _getFilteredDocuments(expiredDocuments);
                        final doc = filteredDocs[index];
                        if (doc == null || !(doc is Map)) {
                          return const SizedBox.shrink();
                        }
                        
                        final docMap = doc as Map<String, dynamic>;
                        final documentName = docMap['document_name']?.toString() ?? 'Unknown';
                        final expiryDate = docMap['expiry_date']?.toString() ?? '-';
                        final status = docMap['status']?.toString() ?? 'expired';
                        final penalty = docMap['penalty']?.toString() ?? '0%';
                        final penaltyStatus = docMap['penalty_status']?.toString() ?? 'Warning';
                        final penaltyPercentage = docMap['penalty_percentage'] ?? 0;

                        // Extract ride type from document name
                        final rideType = documentName.contains('Parcel') ? 'parcel' : 'intercity';
                        final rideId = documentName.split(' - ').last;

                        return InkWell(
                          onTap: () {
                            // Show ride details bottom sheet
                            _showRideDetailsBottomSheet(docMap);
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.shade200,
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // Left Icon
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF369D01).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      rideType == 'parcel' ? Icons.local_shipping : Icons.directions_car,
                                      color: const Color(0xFF369D01),
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Center Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          rideType == 'parcel' ? 'Parcel Ride' : 'Intercity Ride',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[800],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Ride ID: $rideId',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Expired: $expiryDate',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              'Penalty: $penalty',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _getPenaltyColor(penaltyPercentage),
                                              ),
                                            ),
                                            if (penaltyPercentage > 0) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                '₹${_calculatePenaltyAmount(docMap)}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Right Arrow
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey[400],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Penalty History (New Format)
                  if (isNewFormat && penaltyHistory.isNotEmpty) ...[
                    Text(
                      'Penalty History',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: penaltyHistory.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final history = penaltyHistory[index];
                        if (history == null || !(history is Map)) {
                          return const SizedBox.shrink();
                        }
                        
                        final historyMap = history as Map<String, dynamic>;
                        final date = historyMap['date']?.toString() ?? '-';
                        final reason = historyMap['reason']?.toString() ?? 'Unknown';
                        final amount = historyMap['amount'] ?? 0;
                        final amountValue = (amount is num) ? amount.toInt() : 
                                         (amount is String) ? int.tryParse(amount) ?? 0 : 0;
                        final rideType = historyMap['ride_type']?.toString() ?? 'Unknown';
                        final rideAmount = historyMap['ride_amount'] ?? 0;
                        final rideAmountValue = (rideAmount is num) ? rideAmount.toInt() : 
                                             (rideAmount is String) ? int.tryParse(rideAmount) ?? 0 : 0;

                        return Card(
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      rideType.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[600],
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    Text(
                                      date,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Fare',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      '₹$rideAmountValue',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Penalty',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      '₹$amountValue',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    reason,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  // History List (Old Format)
                  if (!isNewFormat) ...[
                    if (expiryHistory.isEmpty)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'No Expiry Records',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You have no expiry penalties yet.',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: expiryHistory.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final history = expiryHistory[index];
                          if (history == null || !(history is Map)) {
                            return const SizedBox.shrink();
                          }
                          
                          final historyMap = history as Map<String, dynamic>;
                          final rideType = historyMap['ride_type']?.toString() ?? 'Unknown';
                          
                          final rideAmountRaw = historyMap['ride_amount'];
                          final rideAmount = (rideAmountRaw is num) ? rideAmountRaw.toInt() : 
                                           (rideAmountRaw is String) ? int.tryParse(rideAmountRaw) ?? 0 : 0;
                          
                          final expiryCountRaw = historyMap['expiry_count'];
                          final expiryCount = (expiryCountRaw is num) ? expiryCountRaw.toInt() : 
                                            (expiryCountRaw is String) ? int.tryParse(expiryCountRaw) ?? 0 : 0;
                          
                          final penaltyPercentRaw = historyMap['penalty_percent'];
                          final penaltyPercent = (penaltyPercentRaw is num) ? penaltyPercentRaw.toInt() : 
                                               (penaltyPercentRaw is String) ? int.tryParse(penaltyPercentRaw) ?? 0 : 0;
                          
                          final penaltyAmountRaw = historyMap['penalty_amount'];
                          final penaltyAmount = (penaltyAmountRaw is num) ? penaltyAmountRaw.toInt() : 
                                               (penaltyAmountRaw is String) ? int.tryParse(penaltyAmountRaw) ?? 0 : 0;
                          
                          final walletBeforeRaw = historyMap['wallet_before'];
                          final walletBefore = (walletBeforeRaw is num) ? walletBeforeRaw.toInt() : 
                                              (walletBeforeRaw is String) ? int.tryParse(walletBeforeRaw) ?? 0 : 0;
                          
                          final walletAfterRaw = historyMap['wallet_after'];
                          final walletAfter = (walletAfterRaw is num) ? walletAfterRaw.toInt() : 
                                             (walletAfterRaw is String) ? int.tryParse(walletAfterRaw) ?? 0 : 0;
                          
                          final expiryDate = _formatDate(historyMap['expiry_date']);
                          final expiryReason = historyMap['expiry_reason']?.toString() ?? 'Driver No Show';

                          return Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        rideType.toString().toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[600],
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      Text(
                                        expiryDate,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Ride Amount',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        '₹$rideAmount',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Expiry Number',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        _getExpiryNumberText(expiryCount),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: expiryCount >= 5 ? Colors.red : Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Penalty',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        _getPenaltyText(penaltyPercent, penaltyAmount),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: penaltyPercent > 0 ? Colors.red : Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (penaltyPercent > 0) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Wallet Before',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                        Text(
                                          '₹$walletBefore',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Wallet After',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                        Text(
                                          '₹$walletAfter',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      expiryReason,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],

                  // Empty State for New Format
                  if (isNewFormat && expiredDocuments.isEmpty && penaltyHistory.isEmpty)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            'No expiry penalties found',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'You have no expiry penalties yet.',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
