import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> notifications = [];
  bool loading = true;
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
  }

  Future<void> fetchNotifications() async {
    try {
      setState(() => loading = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/user/notifications'),
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
      print('Error fetching notifications: $e');
      setState(() => loading = false);
    }
  }

  Future<void> markAsRead(int notificationId) async {
    try {
      final token = await storage.read(key: 'jwt');
      await http.post(
        Uri.parse('$serverBaseUrl/api/user/notifications/$notificationId/read'),
        headers: {"Authorization": "Bearer $token"},
      );
      fetchNotifications();
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/user/notifications/read-all'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read'),
            backgroundColor: Colors.green,
          ),
        );
        fetchNotifications();
      }
    } catch (e) {
      print('Error marking all as read: $e');
    }
  }

  Future<void> deleteNotification(int notificationId) async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.delete(
        Uri.parse('$serverBaseUrl/api/user/notifications/$notificationId'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification deleted'),
            backgroundColor: Colors.green,
          ),
        );
        fetchNotifications();
      }
    } catch (e) {
      print('Error deleting notification: $e');
    }
  }

  Future<void> clearReadNotifications() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear Read Notifications?'),
        content: const Text(
            'This will delete all notifications you have already read.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final token = await storage.read(key: 'jwt');
        final response = await http.delete(
          Uri.parse('$serverBaseUrl/api/user/notifications/clear-read'),
          headers: {"Authorization": "Bearer $token"},
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${data['count']} read notifications cleared'),
              backgroundColor: Colors.green,
            ),
          );
          fetchNotifications();
        }
      } catch (e) {
        print('Error clearing read notifications: $e');
      }
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'new_order':
        return Icons
            .shopping_cart_checkout_outlined; // ✅ Clear new order/checkout icon
      case 'order_accepted':
      case 'order_confirmed':
        return Icons.check_circle_outline; // ✅ Clear confirmation icon
      case 'order_cancelled':
        return Icons.cancel_outlined; // ✅ Clear cancellation icon
      case 'order_shipped':
        return Icons
            .local_shipping_outlined; // ✅ Clear shipping/delivery truck icon
      case 'order_delivered':
        return Icons.done_all_outlined; // ✅ Clear completed/delivered icon
      case 'seller_approved':
        return Icons.verified_outlined; // ✅ Clear verification/approval icon
      case 'seller_rejected':
        return Icons.error_outline; // ✅ Clear error/rejection icon
      case 'product_added':
        return Icons.inventory_2_outlined; // ✅ Clear product/inventory icon
      case 'message':
        return Icons.chat_bubble_outline; // ✅ Clear message/chat icon
      default:
        return Icons
            .notifications_outlined; // ✅ Clear default notification bell
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'new_order':
        return Colors.blue;
      case 'order_accepted':
      case 'order_confirmed':
      case 'seller_approved':
        return Colors.green;
      case 'order_cancelled':
      case 'seller_rejected':
        return Colors.red;
      case 'order_shipped':
        return Colors.orange;
      case 'order_delivered':
        return Colors.purple;
      case 'product_added':
        return Colors.teal;
      case 'message':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications', style: GoogleFonts.poppins()),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (notifications.any((n) => n['is_read'] == 0))
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: markAllAsRead,
              tooltip: 'Mark all as read',
            ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'clear_read',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, size: 20),
                    SizedBox(width: 8),
                    Text('Clear read notifications'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 8),
                    Text('Refresh'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'clear_read') {
                clearReadNotifications();
              } else if (value == 'refresh') {
                fetchNotifications();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchNotifications,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : notifications.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_off,
                            size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You\'re all caught up!',
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
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      final isUnread = notification['is_read'] == 0;
                      final notifColor =
                          _getNotificationColor(notification['type'] ?? '');
                      final notifIcon =
                          _getNotificationIcon(notification['type'] ?? '');

                      return Dismissible(
                        key: Key(notification['id'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.delete,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Delete Notification?'),
                              content: const Text(
                                  'Are you sure you want to delete this notification?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) {
                          deleteNotification(notification['id']);
                        },
                        child: Card(
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
                            contentPadding: const EdgeInsets.all(16),
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor: notifColor.withOpacity(0.2),
                                  radius: 28,
                                  child: Icon(
                                    notifIcon,
                                    color: notifColor,
                                    size: 28,
                                  ),
                                ),
                                if (isUnread)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              notification['title'] ?? 'Notification',
                              style: GoogleFonts.poppins(
                                fontWeight: isUnread
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                Text(
                                  notification['message'] ?? '',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatTime(notification['created_at']
                                              ?.toString() ??
                                          ''),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: isUnread
                                ? IconButton(
                                    icon: const Icon(Icons.mark_email_read,
                                        color: Colors.blue),
                                    onPressed: () =>
                                        markAsRead(notification['id']),
                                    tooltip: 'Mark as read',
                                  )
                                : null,
                            onTap: () {
                              if (isUnread) {
                                markAsRead(notification['id']);
                              }
                              // Handle notification tap based on type
                              // You can navigate to relevant screens here
                            },
                          ),
                        ),
                      );
                    },
                  ),
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
      if (difference.inDays == 1) return 'Yesterday';
      if (difference.inDays < 7) return '${difference.inDays} days ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }
}
