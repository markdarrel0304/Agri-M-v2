import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key});

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  final storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> payments = [];
  bool loading = true;
  String filterStatus = 'all';

  String get serverUrl =>
      Platform.isAndroid ? "http://10.0.2.2:8881" : "http://localhost:8881";

  @override
  void initState() {
    super.initState();
    fetchPaymentHistory();
  }

  Future<void> fetchPaymentHistory() async {
    try {
      setState(() => loading = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverUrl/api/payments/history'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          payments = List<Map<String, dynamic>>.from(data['payments']);
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }
    } catch (e) {
      print('Error fetching payment history: $e');
      setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get filteredPayments {
    if (filterStatus == 'all') return payments;
    return payments.where((p) => p['escrow_status'] == filterStatus).toList();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'held':
        return Colors.orange;
      case 'released':
        return Colors.green;
      case 'refunded':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'held':
        return Icons.lock;
      case 'released':
        return Icons.check_circle;
      case 'refunded':
        return Icons.refresh;
      default:
        return Icons.info;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'held':
        return 'In Escrow';
      case 'released':
        return 'Released';
      case 'refunded':
        return 'Refunded';
      default:
        return status;
    }
  }

  String _getPaymentMethodLabel(String method) {
    switch (method.toLowerCase()) {
      case 'gcash':
        return 'GCash';
      case 'card':
        return 'Credit/Debit Card';
      case 'bank':
        return 'Bank Transfer';
      case 'cod':
        return 'Cash on Delivery';
      default:
        return method;
    }
  }

  IconData _getPaymentMethodIcon(String method) {
    switch (method.toLowerCase()) {
      case 'gcash':
        return Icons.phone_android;
      case 'card':
        return Icons.credit_card;
      case 'bank':
        return Icons.account_balance;
      case 'cod':
        return Icons.local_shipping;
      default:
        return Icons.payment;
    }
  }

  // ✅ FIXED: Convert UTC to Philippine Time (UTC+8)
  String _formatDate(String? timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      // Parse as UTC then convert to Philippine Time
      final utcDate = DateTime.parse(timestamp).toUtc();
      final phTime =
          utcDate.add(const Duration(hours: 8)); // Add 8 hours for PH
      return DateFormat('MMM dd, yyyy • hh:mm a').format(phTime);
    } catch (e) {
      return 'Invalid date';
    }
  }

  // ✅ NEW: Format for display in relative time
  String _formatRelativeTime(String? timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final utcDate = DateTime.parse(timestamp).toUtc();
      final phTime = utcDate.add(const Duration(hours: 8));
      final now = DateTime.now();
      final difference = now.difference(phTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return DateFormat('MMM dd, yyyy').format(phTime);
      }
    } catch (e) {
      return 'Invalid date';
    }
  }

  void _showPaymentDetails(Map<String, dynamic> payment) {
    final isBuyer = payment['user_role'] == 'buyer';
    final escrowStatus = payment['escrow_status'] ?? 'unknown';
    final statusColor = _getStatusColor(escrowStatus);

    final amount = payment['amount'] is String
        ? double.tryParse(payment['amount']) ?? 0.0
        : (payment['amount'] ?? 0.0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getStatusIcon(escrowStatus),
                      color: statusColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment Details',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isBuyer ? 'You paid' : 'You received',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 32),

              // Amount
              Center(
                child: Column(
                  children: [
                    Text(
                      NumberFormat.currency(symbol: '₱').format(amount),
                      style: GoogleFonts.poppins(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getStatusIcon(escrowStatus),
                              size: 16, color: statusColor),
                          const SizedBox(width: 6),
                          Text(
                            _getStatusLabel(escrowStatus),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Product Info
              _buildDetailRow('Product', payment['product_name'] ?? 'Unknown'),
              _buildDetailRow('Quantity', '${payment['quantity'] ?? 'N/A'}'),

              const Divider(height: 32),

              // Payment Method
              _buildDetailRow(
                'Payment Method',
                _getPaymentMethodLabel(payment['payment_method'] ?? ''),
                icon: _getPaymentMethodIcon(payment['payment_method'] ?? ''),
              ),

              if (payment['reference_number'] != null)
                _buildDetailRow('Reference #', payment['reference_number']),

              // Method-specific details
              if (payment['phone_number'] != null)
                _buildDetailRow('Phone Number', payment['phone_number']),
              if (payment['card_last4'] != null)
                _buildDetailRow('Card', '•••• ${payment['card_last4']}'),
              if (payment['bank_name'] != null)
                _buildDetailRow('Bank', payment['bank_name']),

              const Divider(height: 32),

              // Timeline
              Row(
                children: [
                  Text(
                    'Transaction Timeline',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time,
                            size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Philippine Time',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildTimelineItem(
                'Payment Completed',
                _formatDate(payment['completed_at']),
                Icons.check_circle,
                Colors.green,
              ),

              if (payment['released_at'] != null)
                _buildTimelineItem(
                  'Escrow Released',
                  _formatDate(payment['released_at']),
                  Icons.lock_open,
                  Colors.blue,
                ),

              if (payment['refunded_at'] != null)
                _buildTimelineItem(
                  'Refunded',
                  _formatDate(payment['refunded_at']),
                  Icons.refresh,
                  Colors.orange,
                ),

              const SizedBox(height: 24),

              // Escrow Info
              if (escrowStatus == 'held')
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue.shade700, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isBuyer
                              ? 'Your payment is held securely. It will be released to the seller after you confirm delivery.'
                              : 'Payment is held in escrow. You will receive it after buyer confirms delivery.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade700,
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

  Widget _buildDetailRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.grey.shade600),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
      String title, String time, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Payment History', style: GoogleFonts.poppins()),
        backgroundColor: isDark ? Colors.green.shade900 : Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchPaymentHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all', payments.length),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'In Escrow',
                    'held',
                    payments.where((p) => p['escrow_status'] == 'held').length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Released',
                    'released',
                    payments
                        .where((p) => p['escrow_status'] == 'released')
                        .length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Refunded',
                    'refunded',
                    payments
                        .where((p) => p['escrow_status'] == 'refunded')
                        .length,
                  ),
                ],
              ),
            ),
          ),

          // Payment List
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : filteredPayments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.payment,
                                size: 80, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No payments found',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: fetchPaymentHistory,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredPayments.length,
                          itemBuilder: (context, index) {
                            final payment = filteredPayments[index];
                            final isBuyer = payment['user_role'] == 'buyer';
                            final escrowStatus =
                                payment['escrow_status'] ?? 'unknown';
                            final statusColor = _getStatusColor(escrowStatus);

                            final amount = payment['amount'] is String
                                ? double.tryParse(payment['amount']) ?? 0.0
                                : (payment['amount'] ?? 0.0);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                onTap: () => _showPaymentDetails(payment),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color:
                                                  statusColor.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              _getPaymentMethodIcon(
                                                  payment['payment_method'] ??
                                                      ''),
                                              color: statusColor,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  payment['product_name'] ??
                                                      'Unknown',
                                                  style: GoogleFonts.poppins(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _getPaymentMethodLabel(payment[
                                                          'payment_method'] ??
                                                      ''),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                NumberFormat.currency(
                                                        symbol: '₱')
                                                    .format(amount),
                                                style: GoogleFonts.poppins(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green.shade700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: statusColor
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: statusColor),
                                                ),
                                                child: Text(
                                                  _getStatusLabel(escrowStatus),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Icon(
                                            isBuyer
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isBuyer
                                                ? 'You paid'
                                                : 'You received',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(Icons.access_time,
                                              size: 14,
                                              color: Colors.grey.shade600),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatRelativeTime(
                                                payment['completed_at']),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = filterStatus == value;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          filterStatus = value;
        });
      },
      selectedColor: Colors.green.shade700,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
