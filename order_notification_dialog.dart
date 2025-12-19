import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class OrderNotificationDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onAccepted;
  final VoidCallback onDeclined;

  const OrderNotificationDialog({
    super.key,
    required this.order,
    required this.onAccepted,
    required this.onDeclined,
  });

  @override
  State<OrderNotificationDialog> createState() =>
      _OrderNotificationDialogState();
}

class _OrderNotificationDialogState extends State<OrderNotificationDialog>
    with SingleTickerProviderStateMixin {
  final storage = const FlutterSecureStorage();
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isProcessing = false;

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
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _acceptOrder() async {
    setState(() => _isProcessing = true);

    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/orders/${widget.order['id']}/accept'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.of(context).pop();
          widget.onAccepted();
          _showSnackBar('Order accepted successfully!', Colors.green);
        }
      } else {
        final data = json.decode(response.body);
        if (mounted) {
          _showSnackBar(data['error'] ?? 'Failed to accept order', Colors.red);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _declineOrder() async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Decline Order?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to decline this order?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
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
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason (Optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: 'Tell buyer why...',
                prefixIcon: const Icon(Icons.message),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Decline Order'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);

      try {
        final token = await storage.read(key: 'jwt');
        final response = await http.post(
          Uri.parse(
              '$serverBaseUrl/api/orders/${widget.order['id']}/seller-cancel'),
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
          if (mounted) {
            Navigator.of(context).pop();
            widget.onDeclined();
            _showSnackBar('Order declined. Product returned to marketplace.',
                Colors.orange);
          }
        } else {
          final data = json.decode(response.body);
          if (mounted) {
            _showSnackBar(
                data['error'] ?? 'Failed to decline order', Colors.red);
          }
        }
      } catch (e) {
        if (mounted) {
          _showSnackBar('Error: $e', Colors.red);
        }
      } finally {
        if (mounted) {
          setState(() => _isProcessing = false);
        }
      }
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
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with animation
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade700, Colors.blue.shade500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shopping_bag,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🔔 New Order!',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'You have a new order request',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Image and Info
                    Row(
                      children: [
                        if (widget.order['product_image'] != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              widget.order['product_image']
                                      .toString()
                                      .startsWith('http')
                                  ? widget.order['product_image']
                                  : '$serverBaseUrl${widget.order['product_image']}',
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.image, size: 40),
                                );
                              },
                            ),
                          )
                        else
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.shopping_bag, size: 40),
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.order['product_name'] ?? 'Product',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Quantity: ${widget.order['quantity']}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₱${widget.order['price']}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Buyer Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person,
                                  size: 18, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Buyer Information',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.order['buyer_name'] ?? 'Unknown',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.order['buyer_email'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.order['buyer_email'],
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Info box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Accept to confirm order or Decline to return product to marketplace',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _isProcessing
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _declineOrder,
                              icon: const Icon(Icons.close, size: 20),
                              label: const Text('Decline'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(
                                    color: Colors.red.shade700, width: 2),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _acceptOrder,
                              icon: const Icon(Icons.check_circle, size: 20),
                              label: const Text('Accept Order'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
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
}

// Helper function to show the dialog
Future<void> showOrderNotificationDialog(
  BuildContext context,
  Map<String, dynamic> order,
  VoidCallback onAccepted,
  VoidCallback onDeclined,
) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => OrderNotificationDialog(
      order: order,
      onAccepted: onAccepted,
      onDeclined: onDeclined,
    ),
  );
}

// Function to check for new orders periodically
Future<Map<String, dynamic>?> checkForNewOrders(
    FlutterSecureStorage storage, String serverBaseUrl) async {
  try {
    final token = await storage.read(key: 'jwt');
    if (token == null) return null;

    final response = await http.get(
      Uri.parse('$serverBaseUrl/api/seller/latest-pending-order'),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['has_new_order'] == true) {
        return data['order'];
      }
    }
  } catch (e) {
    print('Error checking for new orders: $e');
  }
  return null;
}
