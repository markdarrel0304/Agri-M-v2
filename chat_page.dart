import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'payment_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final storage = const FlutterSecureStorage();
  final messageController = TextEditingController();
  final scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> conversations = [];
  bool loading = true;
  bool uploading = false;
  String? selectedConvId;
  String? selectedUserName;
  String currentUserId = '';
  Map<String, dynamic>? activeOrder;
  List<XFile> selectedImages = []; // ✅ Store selected images

  String get serverUrl =>
      Platform.isAndroid ? "http://10.0.2.2:8881" : "http://localhost:8881";

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final token = await storage.read(key: 'jwt');
    if (token == null) return;

    final response = await http.get(
      Uri.parse('$serverUrl/api/me'),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      currentUserId = json.decode(response.body)['user']['id'].toString();
      _loadConversations();
    }
  }

  Future<void> _loadConversations() async {
    try {
      setState(() => loading = true);
      final token = await storage.read(key: 'jwt');
      final response = await http.get(
        Uri.parse('$serverUrl/api/conversations'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        setState(() {
          conversations = List<Map<String, dynamic>>.from(
              json.decode(response.body)['conversations']);
          loading = false;
        });
      }
    } catch (e) {
      setState(() => loading = false);
    }
  }

  Future<void> _loadMessages(String convId) async {
    final token = await storage.read(key: 'jwt');
    final response = await http.get(
      Uri.parse('$serverUrl/api/messages/$convId'),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      setState(() {
        messages = List<Map<String, dynamic>>.from(
            json.decode(response.body)['messages']);
      });
      _loadActiveOrder(convId);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _markAsShipped(int orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Shipped'),
        content: const Text(
          'Have you shipped this order? The buyer will be notified and can confirm receipt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            child: const Text('Mark as Shipped'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverUrl/api/orders/$orderId/mark-shipped'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'shipment_proof': null, // Optional: Add tracking number
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar('Order marked as shipped!', Colors.green);
        _loadMessages(selectedConvId!);
        _loadActiveOrder(selectedConvId!);
      } else {
        final error = json.decode(response.body);
        _showSnackBar(
            error['error'] ?? 'Failed to mark as shipped', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _completeOrder(int orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Receipt'),
        content: const Text(
          'Have you received this order in good condition? Payment will be released to the seller.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            child: const Text('Confirm Receipt'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverUrl/api/orders/$orderId/complete'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        _showSnackBar(
            'Order completed! Payment released to seller.', Colors.green);
        _loadMessages(selectedConvId!);
        _loadActiveOrder(selectedConvId!);
      } else {
        final error = json.decode(response.body);
        _showSnackBar(error['error'] ?? 'Failed to complete order', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _cancelOrder(int orderId) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure you want to cancel this order?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverUrl/api/orders/$orderId/seller-cancel-accepted'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'reason': reasonController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar(
            'Order cancelled. Buyer will be refunded.', Colors.orange);
        _loadMessages(selectedConvId!);
        _loadActiveOrder(selectedConvId!);
      } else {
        final error = json.decode(response.body);
        _showSnackBar(error['error'] ?? 'Failed to cancel order', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _raiseDispute(int orderId) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raise Dispute'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please explain the issue with this order:'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason *',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: const Text('Submit Dispute'),
          ),
        ],
      ),
    );

    if (confirmed != true || reasonController.text.trim().isEmpty) return;

    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverUrl/api/orders/$orderId/dispute'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'reason': reasonController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar(
            'Dispute raised. Admin will review your case.', Colors.orange);
        _loadMessages(selectedConvId!);
        _loadActiveOrder(selectedConvId!);
      } else {
        final error = json.decode(response.body);
        _showSnackBar(error['error'] ?? 'Failed to raise dispute', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _loadActiveOrder(String convId) async {
    final token = await storage.read(key: 'jwt');
    final response = await http.get(
      Uri.parse('$serverUrl/api/orders/by-conversation/$convId'),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        activeOrder = data['has_active_order'] ? data : null;
      });
    }
  }

  Future<void> _sendMessage() async {
    if (messageController.text.trim().isEmpty || selectedConvId == null) return;

    final token = await storage.read(key: 'jwt');
    final text = messageController.text.trim();
    messageController.clear();

    await http.post(
      Uri.parse('$serverUrl/api/messages'),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: json.encode({
        'conversation_id': selectedConvId,
        'message': text,
      }),
    );

    _loadMessages(selectedConvId!);
  }

  // 📸 ✅ NEW: Select Multiple Images from Gallery
  Future<void> _selectImages() async {
    if (selectedConvId == null) return;

    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (images.isEmpty) return;

      setState(() {
        selectedImages.addAll(images);
      });

      // Show preview dialog
      _showImagePreview();
    } catch (e) {
      _showSnackBar('Error selecting images: $e', Colors.red);
    }
  }

  // 📷 ✅ NEW: Take Photo with Camera
  Future<void> _takePhoto() async {
    if (selectedConvId == null) return;

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo == null) return;

      setState(() {
        selectedImages.add(photo);
      });

      // Show preview dialog
      _showImagePreview();
    } catch (e) {
      _showSnackBar('Error taking photo: $e', Colors.red);
    }
  }

  // 🖼️ ✅ NEW: Show Image Preview Dialog with Send Button
  void _showImagePreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Selected Images (${selectedImages.length})',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          setState(() => selectedImages.clear());
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),

                // Image Grid Preview
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: selectedImages.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(selectedImages[index].path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                          // Remove button
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  selectedImages.removeAt(index);
                                });
                                setState(() {}); // Update parent state
                                if (selectedImages.isEmpty) {
                                  Navigator.pop(context);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // Action Buttons
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade300,
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Add More Button
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _selectImages();
                        },
                        icon: const Icon(Icons.add_photo_alternate),
                        label: const Text('Add More'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Camera Button
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _takePhoto();
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                        ),
                      ),
                      const Spacer(),
                      // Send Button
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _sendSelectedImages();
                        },
                        icon: const Icon(Icons.send),
                        label: Text('Send (${selectedImages.length})'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _initiatePayment(Map<String, dynamic> order) async {
    // ✅ Removed unnecessary null check since order is non-nullable

    // ✅ orderId is now used in the Navigator.push call
    final orderId = order['order']['id'];
    final amount = order['order']['price'] is String
        ? double.parse(order['order']['price'])
        : order['order']['price'].toDouble();
    final productName = order['order']['product_name'] ?? 'Product';

    // Navigate to payment page
    final paymentSuccess = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentPage(
          orderId: orderId, // ✅ Now using the variable
          amount: amount,
          productName: productName,
        ),
      ),
    );

    if (paymentSuccess == true) {
      // Reload order status
      if (selectedConvId != null) {
        _loadActiveOrder(selectedConvId!);
      }

      _showSnackBar('Payment completed successfully!', Colors.green);
    }
  }

  // 📤 ✅ NEW: Send All Selected Images
  Future<void> _sendSelectedImages() async {
    if (selectedImages.isEmpty || selectedConvId == null) return;

    setState(() => uploading = true);

    int successCount = 0;
    int failCount = 0;

    for (var image in selectedImages) {
      try {
        final token = await storage.read(key: 'jwt');
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$serverUrl/api/messages/upload-media'),
        );

        request.headers['Authorization'] = 'Bearer $token';
        request.fields['conversation_id'] = selectedConvId!;

        var stream = http.ByteStream(File(image.path).openRead());
        var length = await File(image.path).length();
        var multipartFile = http.MultipartFile(
          'media',
          stream,
          length,
          filename: image.path.split('/').last,
          contentType: http_parser.MediaType('image', 'jpeg'),
        );

        request.files.add(multipartFile);

        var response = await request.send();

        if (response.statusCode == 201) {
          successCount++;
        } else {
          failCount++;
        }
      } catch (e) {
        failCount++;
      }
    }

    setState(() {
      uploading = false;
      selectedImages.clear();
    });

    if (successCount > 0) {
      _loadMessages(selectedConvId!);
      _showSnackBar(
        '$successCount image${successCount > 1 ? 's' : ''} sent successfully!',
        Colors.green,
      );
    }

    if (failCount > 0) {
      _showSnackBar(
        'Failed to send $failCount image${failCount > 1 ? 's' : ''}',
        Colors.orange,
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

  // 🖼️ NEW: Show Full Image
  void _showFullImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl.startsWith('http') ? imageUrl : '$serverUrl$imageUrl',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.broken_image,
                    size: 100,
                    color: Colors.white,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(selectedUserName ?? 'Messages',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: isDark ? Colors.blue.shade900 : Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadConversations();
              if (selectedConvId != null) _loadMessages(selectedConvId!);
            },
          ),
        ],
      ),
      body: MediaQuery.of(context).size.width > 600
          ? Row(children: [
              SizedBox(width: 320, child: _buildSidebar()),
              Expanded(child: _buildChatArea()),
            ])
          : (selectedConvId == null ? _buildSidebar() : _buildChatArea()),
    );
  }

  Widget _buildOrderActionsBar() {
    if (activeOrder == null || activeOrder!['has_active_order'] != true) {
      return const SizedBox.shrink();
    }

    final order = activeOrder!['order'];
    final orderStatus = order['status']?.toString() ?? '';
    final paymentStatus = order['payment_status']?.toString() ?? 'unpaid';

    // ✅ Hide entire bar if order is completed or cancelled
    if (orderStatus == 'Completed' || orderStatus == 'Cancelled') {
      return const SizedBox.shrink();
    }

    final isBuyer = activeOrder!['is_buyer'] == true;
    final isSeller = activeOrder!['is_seller'] == true;
    final canPay = activeOrder!['can_pay'] == true; // ✅ NEW
    final canShip = activeOrder!['can_ship'] == true;
    final canCancel = activeOrder!['can_cancel'] == true;
    final canComplete = activeOrder!['can_complete'] == true;
    final canDispute = activeOrder!['can_dispute'] == true;

    print('📝 Order Actions Check:');
    print('  Status: $orderStatus');
    print('  Payment Status: $paymentStatus');
    print('  Is Buyer: $isBuyer');
    print('  Is Seller: $isSeller');
    print('  Can Pay: $canPay');
    print('  Can Ship: $canShip');
    print('  Can Cancel: $canCancel');
    print('  Can Complete: $canComplete');
    print('  Can Dispute: $canDispute');

    List<Widget> actions = [];

    // 💳 BUYER: Pay for Order (BEFORE shipping)
    if (isBuyer && canPay) {
      actions.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _initiatePayment(activeOrder!),
            icon: const Icon(Icons.payment, size: 18),
            label: const Text('Pay Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      );
    }

    // 🚚 SELLER: Mark as Shipped (AFTER payment)
    if (isSeller && canShip) {
      actions.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _markAsShipped(order['id']),
            icon: const Icon(Icons.local_shipping, size: 18),
            label: const Text('Mark as Shipped'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      );
    }

    // ❌ SELLER: Cancel Order
    if (isSeller && canCancel) {
      actions.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _cancelOrder(order['id']),
            icon: const Icon(Icons.cancel, size: 18),
            label: const Text('Cancel Order'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade700),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      );
    }

    // ✅ BUYER: Complete Order (AFTER shipping and payment)
    if (isBuyer && canComplete) {
      actions.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _completeOrder(order['id']),
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Confirm Receipt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      );
    }

    // ⚠️ BOTH: Raise Dispute (AFTER payment)
    if (canDispute) {
      actions.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _raiseDispute(order['id']),
            icon: const Icon(Icons.warning, size: 18),
            label: const Text('Dispute'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange.shade700,
              side: BorderSide(color: Colors.orange.shade700),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      );
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.blue.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_bag, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Order: ${order['product_name']} (₱${order['price']})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: actions
                .expand((widget) => [widget, const SizedBox(width: 8)])
                .toList()
              ..removeLast(),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      color: isDark ? theme.cardTheme.color : Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? Colors.blue.shade900 : Colors.blue.shade700,
            child: Row(
              children: [
                Expanded(
                  child: Text('Conversations',
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : conversations.isEmpty
                    ? const Center(child: Text('No conversations'))
                    : ListView.builder(
                        itemCount: conversations.length,
                        itemBuilder: (context, index) {
                          final conv = conversations[index];
                          final isSelected =
                              selectedConvId == conv['id'].toString();

                          return ListTile(
                            selected: isSelected,
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade700,
                              child: Text(
                                conv['other_user_name'][0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(conv['other_user_name']),
                            subtitle: Text(
                              conv['last_message'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              setState(() {
                                selectedConvId = conv['id'].toString();
                                selectedUserName = conv['other_user_name'];
                              });
                              _loadMessages(selectedConvId!);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    if (selectedConvId == null) {
      return Center(
        child: Text('Select a conversation',
            style: GoogleFonts.poppins(fontSize: 18)),
      );
    }

    return Column(
      children: [
        _buildChatHeader(),
        _buildOrderActionsBar(), // ✅ ADD THIS LINE
        Expanded(child: _buildMessagesList()),
        if (uploading)
          LinearProgressIndicator(
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade700),
          ),
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildChatHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.blue.shade700,
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  selectedUserName?[0].toUpperCase() ?? '',
                  style: TextStyle(color: Colors.blue.shade700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selectedUserName ?? '',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // 💳 Payment Status Bar
        if (activeOrder != null &&
            activeOrder!['has_active_order'] == true &&
            activeOrder!['order']['status'] != 'Completed' &&
            activeOrder!['order']['status'] != 'Cancelled') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _getOrderStatusColor(activeOrder!['order']['status']),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  _getOrderStatusIcon(activeOrder!['order']['status']),
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getOrderStatusText(activeOrder!['order']['status'],
                        activeOrder!['order']['payment_status']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Color _getOrderStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Colors.orange.shade700;
      case 'accepted':
      case 'confirmed':
        return Colors.blue.shade700;
      case 'shipped':
        return Colors.purple.shade700;
      case 'completed':
        return Colors.green.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  IconData _getOrderStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
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
      default:
        return Icons.info;
    }
  }

  String _getOrderStatusText(String? status, String? paymentStatus) {
    final isPaid = paymentStatus == 'paid' || paymentStatus == 'completed';

    switch (status?.toLowerCase()) {
      case 'pending':
        return 'Order Pending Seller Confirmation';
      case 'accepted':
        return isPaid
            ? 'Order Paid - Ready for Shipping'
            : '💳 Payment Required - Seller Accepted';
      case 'confirmed':
        return 'Order Confirmed & Paid - Ready to Ship';
      case 'shipped':
        return 'Order Shipped - Confirm When Received';
      case 'completed':
        return '✅ Order Completed Successfully';
      case 'cancelled':
        return 'Order Cancelled';
      default:
        return 'Unknown Status';
    }
  }

  Widget _buildMessagesList() {
    return messages.isEmpty
        ? const Center(child: Text('No messages yet'))
        : ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              final isSender = msg['sender_id'].toString() == currentUserId;
              final messageType = msg['message_type'] ?? 'text';
              final mediaUrl = msg['media_url'];

              return Align(
                alignment:
                    isSender ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  child: messageType == 'image' && mediaUrl != null
                      ? _buildImageMessage(msg, isSender)
                      : _buildTextMessage(msg, isSender),
                ),
              );
            },
          );
  }

  // 🖼️ NEW: Build Image Message
  Widget _buildImageMessage(Map<String, dynamic> msg, bool isSender) {
    final imageUrl = msg['media_url'];

    return Column(
      crossAxisAlignment:
          isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _showFullImage(imageUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl.startsWith('http') ? imageUrl : '$serverUrl$imageUrl',
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey.shade200,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.broken_image, size: 50),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatTime(msg['created_at']?.toString() ?? ''),
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildTextMessage(Map<String, dynamic> msg, bool isSender) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSender ? Colors.blue.shade700 : Colors.grey.shade200,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isSender ? 16 : 4),
          bottomRight: Radius.circular(isSender ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            msg['message'],
            style: TextStyle(
              color: isSender ? Colors.white : Colors.grey.shade900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatTime(msg['created_at']?.toString() ?? ''),
            style: TextStyle(
              fontSize: 10,
              color: isSender ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 📷 Camera Button (opens preview)
            IconButton(
              onPressed: uploading ? null : _takePhoto,
              icon: const Icon(Icons.camera_alt),
              color: Colors.blue.shade700,
              tooltip: 'Take Photo',
            ),
            // 🖼️ Gallery Button (opens preview)
            IconButton(
              onPressed: uploading ? null : _selectImages,
              icon: const Icon(Icons.image),
              color: Colors.blue.shade700,
              tooltip: 'Select Images',
            ),
            // Text Input
            Expanded(
              child: TextField(
                controller: messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
                enabled: !uploading,
              ),
            ),
            const SizedBox(width: 8),
            // Send Button
            Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: uploading ? null : _sendMessage,
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
