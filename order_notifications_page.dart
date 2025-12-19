import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class OrderNotificationsPage extends StatefulWidget {
  const OrderNotificationsPage({super.key});

  @override
  State<OrderNotificationsPage> createState() => _OrderNotificationsPageState();
}

class _OrderNotificationsPageState extends State<OrderNotificationsPage> {
  final storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> pendingOrders = [];
  bool loading = true;
  bool loadingPending = true;
  String userRole = 'buyer';

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
    getUserRole();
    fetchNotifications();
  }

  Future<void> getUserRole() async {
    final role = await storage.read(key: 'role');
    setState(() {
      userRole = role ?? 'buyer';
    });
    if (userRole == 'seller') {
      fetchPendingOrders();
    }
  }

  Future<void> fetchNotifications() async {
    try {
      setState(() => loading = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/order-notifications'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          notifications =
              List<Map<String, dynamic>>.from(data['notifications']);
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }
    } catch (e) {
      setState(() => loading = false);
    }
  }

  Future<void> fetchPendingOrders() async {
    try {
      setState(() => loadingPending = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/seller/pending-orders'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          pendingOrders =
              List<Map<String, dynamic>>.from(data['pending_orders']);
          loadingPending = false;
        });
      } else {
        setState(() => loadingPending = false);
      }
    } catch (e) {
      setState(() => loadingPending = false);
    }
  }

  Future<void> markAsRead(int notificationId) async {
    try {
      final token = await storage.read(key: 'jwt');
      await http.post(
        Uri.parse(
            '$serverBaseUrl/api/order-notifications/$notificationId/read'),
        headers: {"Authorization": "Bearer $token"},
      );
      fetchNotifications();
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> acceptOrder(int orderId) async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/orders/$orderId/accept'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order accepted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        fetchPendingOrders();
        fetchNotifications();
      } else {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Failed to accept order'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> cancelOrderBySeller(int orderId) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.cancel_outlined,
                color: Colors.red.shade700), // ✅ Clean icon
            const SizedBox(width: 8),
            const Text('Cancel Order'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to cancel this order?'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Product will return to marketplace',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (Optional)',
                border: OutlineInputBorder(),
                hintText: 'Tell buyer why you cancelled...',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Order'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final token = await storage.read(key: 'jwt');
        final response = await http.post(
          Uri.parse('$serverBaseUrl/api/orders/$orderId/seller-cancel'),
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
          body: json.encode({
            'reason': reasonController.text.trim().isNotEmpty
                ? reasonController.text.trim()
                : null,
          }),
        );

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Order cancelled. Product returned to marketplace.'),
              backgroundColor: Colors.orange,
            ),
          );
          fetchPendingOrders();
          fetchNotifications();
        } else {
          final data = json.decode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error'] ?? 'Failed to cancel order'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ CLEAN, RECOGNIZABLE ICONS
  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'new_order':
        return Icons.shopping_cart_checkout_outlined;
      case 'order_accepted':
      case 'order_confirmed':
        return Icons.check_circle_outline;
      case 'order_cancelled':
        return Icons.cancel_outlined;
      case 'order_shipped':
        return Icons.local_shipping_outlined;
      case 'order_delivered':
        return Icons.done_all_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'new_order':
        return Colors.blue;
      case 'order_accepted':
      case 'order_confirmed':
        return Colors.green;
      case 'order_cancelled':
        return Colors.red;
      case 'order_shipped':
        return Colors.orange;
      case 'order_delivered':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: userRole == 'seller' ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Order Notifications', style: GoogleFonts.poppins()),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          bottom: userRole == 'seller'
              ? TabBar(
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: [
                    Tab(
                      icon: Stack(
                        children: [
                          const Icon(Icons
                              .pending_actions_outlined), // ✅ Clean pending icon
                          if (pendingOrders.isNotEmpty)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  pendingOrders.length.toString(),
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                      text: 'Pending Orders',
                    ),
                    const Tab(
                        icon: Icon(Icons
                            .notifications_outlined), // ✅ Clean notification icon
                        text: 'All Notifications'),
                  ],
                )
              : null,
        ),
        body: userRole == 'seller'
            ? TabBarView(
                children: [
                  _buildPendingOrdersTab(),
                  _buildNotificationsTab(),
                ],
              )
            : _buildNotificationsTab(),
      ),
    );
  }

  Widget _buildPendingOrdersTab() {
    return RefreshIndicator(
      onRefresh: fetchPendingOrders,
      child: loadingPending
          ? const Center(child: CircularProgressIndicator())
          : pendingOrders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 80,
                          color: Colors.grey.shade400), // ✅ Clean empty inbox
                      const SizedBox(height: 16),
                      Text(
                        'No pending orders',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'New orders will appear here',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: pendingOrders.length,
                  itemBuilder: (context, index) {
                    final order = pendingOrders[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side:
                            BorderSide(color: Colors.orange.shade200, width: 2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Order header
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      Icons
                                          .hourglass_empty_outlined, // ✅ Clean pending icon
                                      size: 16,
                                      color: Colors.orange.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    'PENDING ACCEPTANCE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Product info
                            Row(
                              children: [
                                if (order['product_image'] != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      order['product_image']
                                              .toString()
                                              .startsWith('http')
                                          ? order['product_image']
                                          : '$serverBaseUrl${order['product_image']}',
                                      width: 70,
                                      height: 70,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Container(
                                          width: 70,
                                          height: 70,
                                          color: Colors.grey[300],
                                          child: const Icon(Icons
                                              .image_outlined), // ✅ Clean icon
                                        );
                                      },
                                    ),
                                  )
                                else
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                        Icons
                                            .shopping_bag_outlined, // ✅ Clean product icon
                                        size: 32),
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        order['product_name'],
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Quantity: ${order['quantity']}',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Total: ₱${order['price']}',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const Divider(height: 24),

                            // Buyer info
                            Row(
                              children: [
                                const Icon(
                                    Icons.person_outline, // ✅ Clean person icon
                                    size: 18,
                                    color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  'Buyer: ${order['buyer_name']}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                    Icons
                                        .calendar_today_outlined, // ✅ Clean calendar icon
                                    size: 18,
                                    color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  order['created_at'] != null
                                      ? _formatDateTime(
                                          order['created_at'].toString())
                                      : '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Action buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        cancelOrderBySeller(order['id']),
                                    icon: const Icon(Icons.cancel_outlined,
                                        size: 18), // ✅ Clean cancel icon
                                    label: const Text('Decline'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                      side: BorderSide(
                                          color: Colors.red.shade700),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => acceptOrder(order['id']),
                                    icon: const Icon(
                                        Icons
                                            .check_circle_outline, // ✅ Clean accept icon
                                        size: 18),
                                    label: const Text('Accept'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      elevation: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildNotificationsTab() {
    return RefreshIndicator(
      onRefresh: fetchNotifications,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                          Icons
                              .notifications_none_outlined, // ✅ Clean no notifications icon
                          size: 80,
                          color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    final isUnread = notification['is_read'] == 0;
                    final notifColor =
                        _getNotificationColor(notification['type']);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: isUnread ? Colors.blue.shade50 : Colors.white,
                      elevation: isUnread ? 3 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isUnread
                              ? Colors.blue.shade200
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: notifColor.withOpacity(0.2),
                          child: Icon(
                            _getNotificationIcon(notification['type']),
                            color: notifColor,
                          ),
                        ),
                        title: Text(
                          notification['message'],
                          style: GoogleFonts.poppins(
                            fontWeight:
                                isUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            if (notification['product_name'] != null)
                              Text('Product: ${notification['product_name']}'),
                            Text(
                              notification['created_at'] != null
                                  ? _formatTime(
                                      notification['created_at'].toString())
                                  : '',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: isUnread
                            ? Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                        onTap: () {
                          if (isUnread) {
                            markAsRead(notification['id']);
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }

  String _formatTime(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inHours < 1) return '${difference.inMinutes}m ago';
      if (difference.inDays < 1) return '${difference.inHours}h ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }

  String _formatDateTime(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}
