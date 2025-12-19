import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class DisputeManagementPage extends StatefulWidget {
  const DisputeManagementPage({super.key});

  @override
  State<DisputeManagementPage> createState() => _DisputeManagementPageState();
}

class _DisputeManagementPageState extends State<DisputeManagementPage>
    with SingleTickerProviderStateMixin {
  final storage = const FlutterSecureStorage();
  late TabController _tabController;

  List<Map<String, dynamic>> allDisputes = [];
  List<Map<String, dynamic>> pendingDisputes = [];
  List<Map<String, dynamic>> resolvedDisputes = [];
  bool loading = true;
  String? errorMessage;

  String get serverUrl =>
      Platform.isAndroid ? "http://10.0.2.2:8881" : "http://localhost:8881";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDisputes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDisputes() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final token = await storage.read(key: 'jwt');

      if (token == null) {
        setState(() {
          loading = false;
          errorMessage = 'No authentication token found. Please log in again.';
        });
        return;
      }

      print('ðŸ”„ Loading disputes from: $serverUrl/api/admin/disputes');
      print('ðŸ”‘ Token exists: ${token.isNotEmpty}');

      final response = await http.get(
        Uri.parse('$serverUrl/api/admin/disputes'),
        headers: {"Authorization": "Bearer $token"},
      ).timeout(const Duration(seconds: 10));

      print('ðŸ“¡ Response status: ${response.statusCode}');
      print('ðŸ“¡ Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('âœ… Data keys: ${data.keys}');

        if (data['disputes'] != null) {
          setState(() {
            allDisputes = List<Map<String, dynamic>>.from(data['disputes']);
            pendingDisputes = allDisputes
                .where((d) => d['status'] == 'pending' || d['status'] == 'open')
                .toList();
            resolvedDisputes =
                allDisputes.where((d) => d['status'] == 'resolved').toList();
            loading = false;
          });
          print('âœ… Loaded ${allDisputes.length} disputes');
          print(
              'âœ… Pending: ${pendingDisputes.length}, Resolved: ${resolvedDisputes.length}');
        } else {
          setState(() {
            loading = false;
            errorMessage = 'No disputes data in response';
          });
          print('âš ï¸ No "disputes" key in response');
        }
      } else {
        setState(() {
          loading = false;
          errorMessage =
              'Server error: ${response.statusCode}\n${response.body}';
        });
        print('âŒ Server error: ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      setState(() {
        loading = false;
        errorMessage = 'Request timeout. Server might be down or slow.';
      });
      print('âŒ Timeout error: $e');
    } on http.ClientException catch (e) {
      setState(() {
        loading = false;
        errorMessage =
            'Network error: $e\n\nPlease check if the server is running at $serverUrl';
      });
      print('âŒ Network error: $e');
    } catch (e) {
      setState(() {
        loading = false;
        errorMessage = 'Unexpected error: $e';
      });
      print('âŒ Unexpected error: $e');
      print('âŒ Error type: ${e.runtimeType}');
    }
  }

  Future<void> _resolveDispute(
      int disputeId, String resolution, String winner) async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverUrl/api/admin/disputes/$disputeId/resolve'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'resolution': resolution,
          'winner': winner, // 'buyer' or 'seller'
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar('Dispute resolved successfully', Colors.green);
        _loadDisputes();
      } else {
        final error = json.decode(response.body);
        _showSnackBar(
            error['error'] ?? 'Failed to resolve dispute', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _showResolveDialog(Map<String, dynamic> dispute) async {
    final reasonController = TextEditingController();
    String? selectedWinner;

    print('🔍 ===== DISPUTE DATA =====');
    print('Full dispute object: $dispute');
    print('Dispute ID: ${dispute['id']}');
    print('Order ID: ${dispute['order_id']}');
    print('Product: ${dispute['product_name']}');
    print('Buyer: ${dispute['buyer_name']}');
    print('Seller: ${dispute['seller_name']}');
    print('=========================');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Resolve Dispute #${dispute['id']}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order: ${dispute['product_name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Amount: â‚±${dispute['order_amount']}'),
                const Divider(height: 24),
                Text(
                  'Buyer: ${dispute['buyer_name']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('Seller: ${dispute['seller_name']}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Divider(height: 24),
                const Text(
                  'Who should receive the funds?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  title: Text('Refund Buyer (${dispute['buyer_name']})'),
                  value: 'buyer',
                  groupValue: selectedWinner,
                  onChanged: (val) => setState(() => selectedWinner = val),
                ),
                RadioListTile<String>(
                  title: Text('Release to Seller (${dispute['seller_name']})'),
                  value: 'seller',
                  groupValue: selectedWinner,
                  onChanged: (val) => setState(() => selectedWinner = val),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Resolution Explanation *',
                    border: OutlineInputBorder(),
                    hintText: 'Explain your decision...',
                  ),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedWinner == null ||
                    reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select winner and provide reason'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
              ),
              child: const Text('Resolve Dispute'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true &&
        selectedWinner != null &&
        reasonController.text.trim().isNotEmpty) {
      await _resolveDispute(
        dispute['order_id'],
        reasonController.text.trim(),
        selectedWinner!,
      );
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dispute Management', style: GoogleFonts.poppins()),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDisputes,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              icon: const Icon(Icons.pending_actions),
              text: 'Pending (${pendingDisputes.length})',
            ),
            Tab(
              icon: const Icon(Icons.check_circle),
              text: 'Resolved (${resolvedDisputes.length})',
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 60,
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 16),
              Text(
                'Error Loading Disputes',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadDisputes,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildDisputeList(pendingDisputes, isPending: true),
        _buildDisputeList(resolvedDisputes, isPending: false),
      ],
    );
  }

  Widget _buildDisputeList(List<Map<String, dynamic>> disputes,
      {required bool isPending}) {
    if (disputes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPending ? Icons.check_circle_outline : Icons.history,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              isPending ? 'No pending disputes' : 'No resolved disputes',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'All disputes are currently ${isPending ? 'resolved' : 'pending'}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDisputes,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: disputes.length,
        itemBuilder: (context, index) {
          final dispute = disputes[index];
          return _buildDisputeCard(dispute, isPending: isPending);
        },
      ),
    );
  }

  Widget _buildDisputeCard(Map<String, dynamic> dispute,
      {required bool isPending}) {
    final createdAt = DateTime.tryParse(_safeString(dispute['created_at']));
    final timeAgo = createdAt != null
        ? _formatTimeAgo(DateTime.now().difference(createdAt))
        : 'Unknown';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPending ? Colors.orange.shade200 : Colors.green.shade200,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPending ? Colors.orange : Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isPending ? 'PENDING' : 'RESOLVED',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Dispute #${dispute['id']}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.shopping_bag, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safeString(dispute['product_name'], 'Unknown Product'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Order #${dispute['order_id']} â€¢ â‚±${_safeString(dispute['order_amount'], '0')}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPartyInfo(
                    'Buyer',
                    _safeString(dispute['buyer_name'], 'Unknown'),
                    Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildPartyInfo(
                    'Seller',
                    _safeString(dispute['seller_name'], 'Unknown'),
                    Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.report_problem,
                          size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Dispute Reason',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _safeString(dispute['reason'], 'No reason provided'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            if (!isPending && dispute['resolution'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.gavel,
                            size: 16, color: Colors.green.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Admin Decision',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Winner: ${_safeString(dispute['winner'], 'N/A').toUpperCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _safeString(
                          dispute['resolution'], 'No resolution provided'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  timeAgo,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Spacer(),
                if (isPending)
                  ElevatedButton.icon(
                    onPressed: () => _showResolveDialog(dispute),
                    icon: const Icon(Icons.gavel, size: 18),
                    label: const Text('Resolve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartyInfo(String role, String name, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            role,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(Duration diff) {
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  String _safeString(dynamic value, [String defaultValue = '']) {
    return value?.toString() ?? defaultValue;
  }
}
