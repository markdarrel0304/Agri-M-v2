import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage>
    with SingleTickerProviderStateMixin {
  final storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> buyerOrders = [];
  List<Map<String, dynamic>> sellerOrders = [];
  bool loading = true;
  String userRole = 'buyer';
  late TabController _tabController;

  String get serverBaseUrl {
    if (Platform.isAndroid) {
      return "http://10.0.2.2:8881";
    } else {
      return "http://localhost:8881";
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _checkUserRole();
    await fetchOrders();
  }

  Future<void> _checkUserRole() async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/me'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          userRole = data['user']['role'] ?? 'buyer';
        });
      }
    } catch (e) {
      print('Error checking user role: $e');
    }
  }

  Future<void> fetchOrders() async {
    setState(() => loading = true);

    try {
      final token = await storage.read(key: 'jwt');

      // Fetch buyer orders (orders I placed)
      final buyerResponse = await http.get(
        Uri.parse('$serverBaseUrl/api/orders'),
        headers: {"Authorization": "Bearer $token"},
      );

      // Fetch seller orders (orders for my products) - ALL orders, not just pending
      final sellerResponse = await http.get(
        Uri.parse('$serverBaseUrl/api/seller/all-orders'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (buyerResponse.statusCode == 200) {
        final buyerData = json.decode(buyerResponse.body);
        setState(() {
          buyerOrders =
              List<Map<String, dynamic>>.from(buyerData['orders'] ?? []);
        });
      }

      if (sellerResponse.statusCode == 200 && userRole == 'seller') {
        final sellerData = json.decode(sellerResponse.body);
        setState(() {
          sellerOrders =
              List<Map<String, dynamic>>.from(sellerData['orders'] ?? []);
        });
      }

      setState(() => loading = false);
    } catch (e) {
      print('Error fetching orders: $e');
      setState(() => loading = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
      case 'confirmed':
        return Colors.blue;
      case 'shipped':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'disputed':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'accepted':
      case 'confirmed':
        return Icons.check_circle;
      case 'shipped':
        return Icons.local_shipping;
      case 'completed':
        return Icons.done_all;
      case 'cancelled':
        return Icons.cancel;
      case 'disputed':
        return Icons.warning;
      default:
        return Icons.info;
    }
  }

  Widget _buildOrderCard(Map<String, dynamic> order, bool isBuyerOrder) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final status = order['status'] ?? 'Unknown';
    final statusColor = _getStatusColor(status);
    final productName = order['product_name'] ?? 'Unknown Product';
    final quantity = order['quantity'] ?? 0;

    final dynamic priceValue = order['price'] ?? 0;
    final double price = priceValue is String
        ? double.tryParse(priceValue) ?? 0.0
        : (priceValue as num).toDouble();

    final createdAt = order['created_at']?.toString().split('T')[0] ?? '';

    final buyerName = order['buyer_name'] ?? 'Unknown';
    final sellerShipped = order['seller_shipped'] == 1;
    final buyerConfirmed = order['buyer_confirmed_receipt'] == 1;

    return Card(
      // ✅ Card automatically adapts to theme
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showOrderDetails(order, isBuyerOrder),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with product name and status badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      productName,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        // ✅ FIXED: Text adapts to theme
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      // ✅ FIXED: Status badge adapts
                      color: isDark
                          ? statusColor.withOpacity(0.2)
                          : statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getStatusIcon(status),
                            size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Order details
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow(
                            Icons.shopping_cart, 'Quantity', '$quantity'),
                        const SizedBox(height: 4),
                        _buildInfoRow(Icons.attach_money, 'Total',
                            '₱${price.toStringAsFixed(2)}'),
                      ],
                    ),
                  ),
                  if (!isBuyerOrder)
                    Expanded(
                      child: _buildInfoRow(Icons.person, 'Buyer', buyerName),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Progress indicators
              if (sellerShipped || buyerConfirmed)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    // ✅ FIXED: Progress box adapts
                    color: isDark
                        ? Colors.blue.shade900.withOpacity(0.3)
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      if (sellerShipped)
                        _buildProgressIndicator(
                          Icons.local_shipping,
                          'Shipped',
                          Colors.blue.shade700,
                        ),
                      if (buyerConfirmed)
                        _buildProgressIndicator(
                          Icons.done_all,
                          'Received',
                          Colors.green.shade700,
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // Footer with date
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 12,
                      color:
                          isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    createdAt,
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600),
                  ),
                  const Spacer(),
                  Text(
                    'Tap for details',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Colors.blue.shade400 : Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 16,
                      color:
                          isDark ? Colors.blue.shade400 : Colors.blue.shade700),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 14,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
        ),
        Text(
          value,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodyMedium?.color),
        ),
      ],
    );
  }

  Widget _buildProgressIndicator(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  void _showOrderDetails(Map<String, dynamic> order, bool isBuyerOrder) {
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
                  Expanded(
                    child: Text(
                      'Order Details',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Order ID
              _buildDetailRow('Order ID', '#${order['id']}'),
              const SizedBox(height: 12),

              // Product Info
              _buildDetailRow('Product', order['product_name'] ?? 'Unknown'),
              const SizedBox(height: 8),
              _buildDetailRow('Quantity', '${order['quantity']}'),
              const SizedBox(height: 8),
              _buildDetailRow('Total Price', '₱${order['price']}'),
              const SizedBox(height: 8),

              // Status
              _buildDetailRow('Status', order['status'] ?? 'Unknown'),
              const SizedBox(height: 8),

              // Role-specific info
              if (!isBuyerOrder) ...[
                _buildDetailRow('Buyer', order['buyer_name'] ?? 'Unknown'),
                const SizedBox(height: 8),
                _buildDetailRow('Buyer Email', order['buyer_email'] ?? 'N/A'),
                const SizedBox(height: 8),
              ],

              // Dates
              _buildDetailRow('Order Date',
                  order['created_at']?.toString().split('T')[0] ?? 'N/A'),

              if (order['shipped_at'] != null) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Shipped Date',
                    order['shipped_at'].toString().split('T')[0]),
              ],

              if (order['completion_date'] != null) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Completed Date',
                    order['completion_date'].toString().split('T')[0]),
              ],

              // Tracking info
              if (order['shipment_proof'] != null &&
                  order['shipment_proof'].toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'Tracking Information',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(order['shipment_proof']),
              ],

              // Dispute info
              if (order['dispute_raised'] == 1) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Dispute Raised',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                      if (order['dispute_reason'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Reason: ${order['dispute_reason']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: TextStyle(
              color: Colors.grey.shade700,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      // ✅ REMOVED: backgroundColor: Colors.grey.shade50
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Orders',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        // ✅ FIXED: Adapt AppBar color
        backgroundColor:
            isDark ? Colors.orange.shade900 : Colors.orange.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchOrders,
            tooltip: 'Refresh',
          ),
        ],
        bottom: userRole == 'seller'
            ? TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'My Purchases', icon: Icon(Icons.shopping_cart)),
                  Tab(text: 'My Sales', icon: Icon(Icons.store)),
                ],
              )
            : null,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : userRole == 'seller'
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrdersList(buyerOrders, true),
                    _buildOrdersList(sellerOrders, false),
                  ],
                )
              : _buildOrdersList(buyerOrders, true),
    );
  }

  Widget _buildOrdersList(
      List<Map<String, dynamic>> orders, bool isBuyerOrder) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isBuyerOrder ? Icons.shopping_bag_outlined : Icons.store_outlined,
              size: 80,
              // ✅ FIXED: Empty state icon adapts
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              isBuyerOrder ? 'No purchases yet' : 'No sales yet',
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isBuyerOrder
                  ? 'Start shopping to see your orders here'
                  : 'Orders from buyers will appear here',
              style: TextStyle(
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                  fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: fetchOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          return _buildOrderCard(orders[index], isBuyerOrder);
        },
      ),
    );
  }
}
