import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'chat_page.dart';
import 'package:http_parser/http_parser.dart' as http_parser;

class CartItem {
  final Map<String, dynamic> product;
  int quantity;
  CartItem({required this.product, this.quantity = 1});

  double get totalPrice {
    final price = double.tryParse(product['price'].toString()) ?? 0;
    return price * quantity;
  }
}

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];
  List<CartItem> cart = [];
  bool loading = true;
  bool isApprovedSeller = false;
  bool checkingSeller = true;
  final storage = const FlutterSecureStorage();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController searchController = TextEditingController();
  String selectedCategory = 'All';
  String? currentUserId;

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
    _loadCurrentUser();
    checkSellerStatus();
    fetchProducts();
    searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/me'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          currentUserId = data['user']['id'].toString();
        });
      }
    } catch (e) {
      print('Error loading current user: $e');
    }
  }

  void _filterProducts() {
    setState(() {
      filteredProducts = products.where((product) {
        final matchesSearch = product['name']
            .toString()
            .toLowerCase()
            .contains(searchController.text.toLowerCase());
        final matchesCategory = selectedCategory == 'All' ||
            product['category'] == selectedCategory;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  String? _getImageUrl(Map<String, dynamic> product) {
    try {
      final imageUrl = product['image_url'];
      if (imageUrl == null || imageUrl.toString().isEmpty) {
        return null;
      }

      final urlString = imageUrl.toString();
      String finalUrl;

      if (urlString.startsWith('http')) {
        finalUrl = urlString;
      } else if (urlString.startsWith('/')) {
        finalUrl = '$serverBaseUrl$urlString';
      } else {
        finalUrl = '$serverBaseUrl/$urlString';
      }

      return finalUrl;
    } catch (e) {
      return null;
    }
  }

  bool _isOwnProduct(Map<String, dynamic> product) {
    if (currentUserId == null) return false;
    return product['seller_id']?.toString() == currentUserId;
  }

  void addToCart(Map<String, dynamic> product) {
    if (_isOwnProduct(product)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot add your own product'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    final stock = product['stock'];
    final hasStock = stock != null && stock.toString().isNotEmpty;
    final stockValue = hasStock ? double.tryParse(stock.toString()) ?? 0 : 0;

    if (hasStock && stockValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Out of stock'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      final idx = cart.indexWhere((i) => i.product['id'] == product['id']);
      if (idx != -1) {
        if (hasStock && cart[idx].quantity + 1 > stockValue) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Max stock reached')),
          );
          return;
        }
        cart[idx].quantity++;
      } else {
        cart.add(CartItem(product: product));
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to cart'),
        backgroundColor: Colors.green,
        action: SnackBarAction(label: 'VIEW', onPressed: showCartDialog),
      ),
    );
  }

  void showCartDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.shopping_cart, color: Colors.green),
              SizedBox(width: 8),
              Text('Cart (${cart.length})'),
            ],
          ),
          content: SizedBox(
            width: 350,
            height: 400,
            child: cart.isEmpty
                ? Center(child: Text('Cart is empty'))
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: cart.length,
                          itemBuilder: (context, i) {
                            final item = cart[i];
                            final p = item.product;
                            return Card(
                              child: ListTile(
                                leading: _getImageUrl(p) != null
                                    ? Image.network(_getImageUrl(p)!,
                                        width: 50, fit: BoxFit.cover)
                                    : Icon(Icons.image),
                                title: Text(p['name'].toString()),
                                subtitle: Text('₱${p['price']}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.remove),
                                      onPressed: () {
                                        setState(() {
                                          if (item.quantity > 1) {
                                            item.quantity--;
                                          } else {
                                            cart.removeAt(i);
                                          }
                                        });
                                        setDialogState(() {});
                                      },
                                    ),
                                    Text('${item.quantity}'),
                                    IconButton(
                                      icon: Icon(Icons.add),
                                      onPressed: () {
                                        setState(() => item.quantity++);
                                        setDialogState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Divider(),
                      Text(
                        'Total: ₱${cart.fold(0.0, (sum, item) => sum + item.totalPrice).toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text('Close')),
            if (cart.isNotEmpty)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  checkoutCart();
                },
                child: Text('Checkout'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> checkoutCart() async {
    if (cart.isEmpty) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm ${cart.length} Order(s)'),
        content: Text('Place all orders in your cart?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Confirm')),
        ],
      ),
    );

    if (result == true) {
      final token = await storage.read(key: 'jwt');
      int success = 0;
      for (var item in cart) {
        try {
          final res = await http.post(
            Uri.parse('$serverBaseUrl/api/orders/create'),
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json"
            },
            body: json.encode(
                {'product_id': item.product['id'], 'quantity': item.quantity}),
          );
          if (res.statusCode == 201) success++;
        } catch (e) {}
      }

      setState(() => cart.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Placed $success orders'),
            backgroundColor: Colors.green),
      );
      await fetchProducts();
    }
  }

  Future<void> checkSellerStatus() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) {
        setState(() {
          isApprovedSeller = false;
          checkingSeller = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/is-approved-seller'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          isApprovedSeller = data['approved'] == true;
          checkingSeller = false;
        });
      } else {
        setState(() {
          isApprovedSeller = false;
          checkingSeller = false;
        });
      }
    } catch (e) {
      setState(() {
        isApprovedSeller = false;
        checkingSeller = false;
      });
    }
  }

  Future<void> fetchProducts() async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/products'),
        headers: token != null ? {"Authorization": "Bearer $token"} : {},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          products = List<Map<String, dynamic>>.from(data['products']);
          filteredProducts = products;
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }
    } catch (e) {
      setState(() => loading = false);
    }
  }

  Future<void> requestSeller() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login first')),
        );
        return;
      }

      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/request-seller'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      final data = json.decode(response.body);

      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Seller Request"),
            content: Text(data['message'] ?? 'Request processed'),
            actions: [
              TextButton(
                child: const Text("OK"),
                onPressed: () {
                  Navigator.pop(context);
                  checkSellerStatus();
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Error"),
            content: Text("Unable to send request: $e"),
            actions: [
              TextButton(
                child: const Text("OK"),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> addProduct(String name, String price, String description,
      {String? imageUrl,
      File? imageFile,
      String? category,
      String? quantity,
      String? unit}) async {
    try {
      print('📤 Starting product upload...');
      final token = await storage.read(key: 'jwt');
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login first')),
        );
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 15),
                Text('Adding product...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverBaseUrl/api/add-product'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['name'] = name;
      request.fields['price'] = price;
      if (description.isNotEmpty) {
        request.fields['description'] = description;
      }
      request.fields['category'] = category ?? 'General';

      if (quantity != null && quantity.isNotEmpty) {
        request.fields['stock'] = quantity;
      }
      if (unit != null && unit.isNotEmpty) {
        request.fields['unit'] = unit;
      }

      if (imageFile != null) {
        var stream = http.ByteStream(imageFile.openRead());
        var length = await imageFile.length();

        String contentType = 'image/jpeg';
        final extension = imageFile.path.split('.').last.toLowerCase();

        if (extension == 'png') {
          contentType = 'image/png';
        } else if (extension == 'jpg' || extension == 'jpeg') {
          contentType = 'image/jpeg';
        } else if (extension == 'gif') {
          contentType = 'image/gif';
        } else if (extension == 'webp') {
          contentType = 'image/webp';
        }

        var multipartFile = http.MultipartFile(
          'image',
          stream,
          length,
          filename: imageFile.path.split('/').last,
          contentType: http_parser.MediaType.parse(contentType),
        );
        request.files.add(multipartFile);
      } else if (imageUrl != null && imageUrl.isNotEmpty) {
        request.fields['image'] = imageUrl;
      }

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Product added successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );

          await fetchProducts();
          await checkSellerStatus();
        }
      } else {
        try {
          final data = json.decode(responseData);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ??
                    data['error'] ??
                    'Failed to add product'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to add product: $responseData'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding product: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> buyProduct(Map<String, dynamic> product) async {
    if (_isOwnProduct(product)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.block, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text('You cannot buy your own product'),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final stock = product['stock'];
    final unit = product['unit'] ?? '';
    final hasStock = stock != null && stock.toString().isNotEmpty;
    final stockValue = hasStock ? double.tryParse(stock.toString()) ?? 0 : 0;

    if (hasStock && stockValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text('This product is out of stock'),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final quantityController = TextEditingController(text: '1');
    final messageController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('Order ${product['name'] ?? 'Product'}'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: MediaQuery.of(ctx).size.width * 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Price per unit: ₱${product['price']}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Seller: ${product['seller_name'] ?? 'Unknown'}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  if (hasStock && stockValue > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2,
                              size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 6),
                          Text(
                            'Available: $stock $unit',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 30),
                  TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.shopping_cart),
                      helperText: hasStock && stockValue > 0
                          ? 'Max: ${stockValue.toInt()} $unit'
                          : null,
                      helperStyle: TextStyle(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: messageController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Message to Seller (Optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.message),
                      hintText: 'Add delivery instructions, questions, etc.',
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 20, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Order Process',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Seller must confirm your order\n'
                          '• You can cancel before confirmation\n'
                          '• After confirmation, only seller can cancel\n'
                          '• Chat with seller for any questions',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.shopping_bag),
              label: const Text("Place Order"),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );

    if (result == true) {
      try {
        final token = await storage.read(key: 'jwt');
        final quantity = int.tryParse(quantityController.text) ?? 1;

        if (quantity <= 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please enter a valid quantity'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        if (hasStock && quantity > stockValue) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Only $stock $unit available. Please adjust your quantity.',
                ),
                backgroundColor: Colors.orange.shade700,
              ),
            );
          }
          return;
        }

        final response = await http.post(
          Uri.parse('$serverBaseUrl/api/orders/create'),
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
          body: json.encode({
            'product_id': product['id'],
            'quantity': quantity,
            'message': messageController.text.trim().isNotEmpty
                ? messageController.text.trim()
                : null,
          }),
        );

        if (response.statusCode == 201) {
          final data = json.decode(response.body);
          if (mounted) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 10),
                    const Flexible(child: Text('Order Placed!')),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your order for ${product['name']} has been sent to the seller.',
                      style: GoogleFonts.poppins(),
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_empty,
                              color: Colors.orange.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Waiting for seller confirmation',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                    ),
                    icon: const Icon(Icons.chat),
                    label: const Text('Chat with Seller'),
                    onPressed: () {
                      Navigator.pop(context);
                      if (data['conversation_id'] != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChatPage(),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          }
        } else {
          final data = json.decode(response.body);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['error'] ?? 'Failed to place order'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void showAddProductDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final descriptionController = TextEditingController();
    final imageUrlController = TextEditingController();
    final quantityController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    File? selectedImage;
    bool useImageFile = false;
    String selectedProductCategory = 'General';
    String selectedUnit = 'Quantity';

    final categories = [
      'General',
      'Rice',
      'Vegetables',
      'Fruits',
      'Tools',
      'Seeds'
    ];
    final units = ['Quantity', 'Kg', 'Lbs', 'Grams', 'Pieces'];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.add_shopping_cart, color: Colors.green.shade700),
                const SizedBox(width: 8),
                const Text("Add New Product"),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: "Product Name",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.shopping_bag),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter product name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedProductCategory,
                        decoration: const InputDecoration(
                          labelText: "Category",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: categories.map((cat) {
                          return DropdownMenuItem(value: cat, child: Text(cat));
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedProductCategory = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: priceController,
                        decoration: const InputDecoration(
                          labelText: "Price",
                          border: OutlineInputBorder(),
                          prefixText: '₱',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter price';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          TextFormField(
                            controller: quantityController,
                            decoration: const InputDecoration(
                              labelText: "Stock/Quantity",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.inventory),
                              hintText: 'e.g. 100',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                if (double.tryParse(value) == null) {
                                  return 'Enter valid number';
                                }
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: selectedUnit,
                            decoration: const InputDecoration(
                              labelText: "Unit",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.straighten),
                            ),
                            items: units.map((unit) {
                              return DropdownMenuItem(
                                  value: unit, child: Text(unit));
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedUnit = value!;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: "Description (Optional)",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  label: Text('URL'),
                                  icon: Icon(Icons.link),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('Gallery'),
                                  icon: Icon(Icons.image),
                                ),
                              ],
                              selected: {useImageFile},
                              onSelectionChanged: (Set<bool> newSelection) {
                                setState(() {
                                  useImageFile = newSelection.first;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!useImageFile)
                        TextFormField(
                          controller: imageUrlController,
                          decoration: const InputDecoration(
                            labelText: "Image URL",
                            border: OutlineInputBorder(),
                            hintText: "https://example.com/image.jpg",
                            prefixIcon: Icon(Icons.link),
                          ),
                        )
                      else
                        Column(
                          children: [
                            if (selectedImage != null) ...[
                              Container(
                                height: 150,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    selectedImage!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final XFile? image = await _picker.pickImage(
                                    source: ImageSource.gallery,
                                    maxWidth: 1920,
                                    maxHeight: 1080,
                                    imageQuality: 85,
                                  );
                                  if (image != null) {
                                    setState(() {
                                      selectedImage = File(image.path);
                                    });
                                  }
                                },
                                icon: const Icon(Icons.photo_library),
                                label: Text(selectedImage == null
                                    ? "Choose from Gallery"
                                    : "Change Image"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add),
                label: const Text("Add Product"),
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(context);
                    addProduct(
                      nameController.text,
                      priceController.text,
                      descriptionController.text,
                      imageUrl: useImageFile ? null : imageUrlController.text,
                      imageFile: useImageFile ? selectedImage : null,
                      category: selectedProductCategory,
                      quantity: quantityController.text,
                      unit: selectedUnit,
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void showProductDetails(Map<String, dynamic> product) {
    final isOwnProduct = _isOwnProduct(product);

    final stock = product['stock'];
    final unit = product['unit'] ?? '';
    final hasStock = stock != null && stock.toString().isNotEmpty;
    final stockValue = hasStock ? double.tryParse(stock.toString()) ?? 0 : 0;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;

        return AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(product['name'].toString())),
              if (isOwnProduct)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade700),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store,
                          size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Your Product',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          content: SizedBox(
            width: screenWidth * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final imageUrl = _getImageUrl(product);

                      if (imageUrl == null) {
                        return Container(
                          height: 200,
                          width: double.infinity,
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.image, size: 50),
                          ),
                        );
                      }

                      return SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 200,
                                width: double.infinity,
                                color: Colors.grey[300],
                                child: const Center(
                                  child:
                                      Icon(Icons.image_not_supported, size: 50),
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                height: 200,
                                width: double.infinity,
                                color: Colors.grey[200],
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes !=
                                            null
                                        ? loadingProgress
                                                .cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  Text(
                    "₱${product['price']}",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (product['category'] != null) ...[
                    Chip(
                      label: Text(product['category'].toString()),
                      backgroundColor: Colors.green.shade100,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (hasStock) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: stockValue > 0
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: stockValue > 0
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            stockValue > 0 ? Icons.check_circle : Icons.error,
                            color: stockValue > 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stockValue > 0 ? 'In Stock' : 'Out of Stock',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: stockValue > 0
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                ),
                                if (stockValue > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Available: $stock $unit',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (product['seller_name'] != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.grey),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Seller: ${product['seller_name']}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (product['description'] != null &&
                      product['description'].toString().isNotEmpty) ...[
                    const Text(
                      'Description:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    Text(product['description'].toString()),
                    const SizedBox(height: 10),
                  ],
                  if (isOwnProduct) ...[
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
                              'This is your product. You cannot purchase your own items.',
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
                  if (!isOwnProduct && hasStock && stockValue <= 0) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This product is currently out of stock. Please check back later.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Close"),
            ),
            if (!isOwnProduct && (!hasStock || stockValue > 0))
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await Future.delayed(const Duration(milliseconds: 200));
                  if (mounted) {
                    await buyProduct(product);
                  }
                },
                child: const Text("Buy Now"),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      'All',
      'General',
      'Rice',
      'Vegetables',
      'Fruits',
      'Tools',
      'Seeds'
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Marketplace"),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.shopping_cart),
                onPressed: showCartDialog,
              ),
              if (cart.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${cart.length}',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final isSelected = selectedCategory == category;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          selectedCategory = category;
                          _filterProducts();
                        });
                      },
                      selectedColor: Colors.green.shade700,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (!checkingSeller && !isApprovedSeller)
              ElevatedButton.icon(
                icon: const Icon(Icons.store),
                label: const Text("Request to be a Seller"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: requestSeller,
              ),
            if (!checkingSeller && isApprovedSeller)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade700),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "You are an approved seller",
                      style: GoogleFonts.poppins(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            loading
                ? const Expanded(
                    child: Center(child: CircularProgressIndicator()))
                : filteredProducts.isEmpty
                    ? const Expanded(
                        child: Center(
                          child: Text(
                            "No products found",
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ),
                      )
                    : Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            await fetchProducts();
                            await checkSellerStatus();
                          },
                          child: GridView.builder(
                            itemCount: filteredProducts.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.8, // Increased from 0.75
                            ),
                            itemBuilder: (context, index) {
                              final product = filteredProducts[index];
                              final isOwnProduct = _isOwnProduct(product);

                              return GestureDetector(
                                onTap: () {
                                  try {
                                    showProductDetails(product);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Error loading product details'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                                child: Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  elevation: 3,
                                  child: Stack(
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // Image section
                                          Expanded(
                                            flex: 3, // Reduced from 3
                                            child: ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                top: Radius.circular(15),
                                              ),
                                              child: Builder(
                                                builder: (context) {
                                                  final imageUrl =
                                                      _getImageUrl(product);

                                                  if (imageUrl == null) {
                                                    return Container(
                                                      color: Colors.grey[300],
                                                      child: const Icon(
                                                          Icons.image,
                                                          size:
                                                              40), // Reduced size
                                                    );
                                                  }

                                                  return Image.network(
                                                    imageUrl,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context,
                                                        error, stackTrace) {
                                                      return Container(
                                                        color: Colors.grey[300],
                                                        child: const Icon(
                                                            Icons.image,
                                                            size: 40),
                                                      );
                                                    },
                                                    loadingBuilder: (context,
                                                        child,
                                                        loadingProgress) {
                                                      if (loadingProgress ==
                                                          null) return child;
                                                      return Container(
                                                        color: Colors.grey[200],
                                                        child: Center(
                                                          child:
                                                              CircularProgressIndicator(
                                                            value: loadingProgress
                                                                        .expectedTotalBytes !=
                                                                    null
                                                                ? loadingProgress
                                                                        .cumulativeBytesLoaded /
                                                                    loadingProgress
                                                                        .expectedTotalBytes!
                                                                : null,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          // Product info section
                                          Expanded(
                                            flex: 2, // Increased from 2
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment
                                                    .spaceBetween, // Better spacing
                                                children: [
                                                  // Product name
                                                  Text(
                                                    product['name'].toString(),
                                                    style: GoogleFonts.poppins(
                                                      fontSize:
                                                          12, // Reduced size
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),

                                                  // Price
                                                  Text(
                                                    "₱${product['price']}",
                                                    style: TextStyle(
                                                      fontSize:
                                                          14, // Reduced size
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          Colors.green.shade700,
                                                    ),
                                                  ),

                                                  // Add to Cart button (only if not own product)
                                                  if (!isOwnProduct)
                                                    SizedBox(
                                                      height:
                                                          30, // Fixed height
                                                      width: double.infinity,
                                                      child:
                                                          ElevatedButton.icon(
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          padding: EdgeInsets
                                                              .zero, // Reduced padding
                                                          backgroundColor:
                                                              Colors.green,
                                                          foregroundColor:
                                                              Colors.white,
                                                        ),
                                                        icon: Icon(
                                                          Icons
                                                              .add_shopping_cart,
                                                          size:
                                                              14, // Smaller icon
                                                        ),
                                                        label: Text(
                                                          'Cart',
                                                          style: TextStyle(
                                                            fontSize:
                                                                12, // Smaller text
                                                          ),
                                                        ),
                                                        onPressed: () =>
                                                            addToCart(product),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isOwnProduct)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 3), // Reduced padding
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade700,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      10), // Slightly smaller
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.2),
                                                  blurRadius: 3,
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.store,
                                                    size: 10, // Smaller icon
                                                    color: Colors.white),
                                                const SizedBox(width: 3),
                                                Text(
                                                  'Yours',
                                                  style: TextStyle(
                                                    fontSize: 9, // Smaller text
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
          ],
        ),
      ),
      floatingActionButton: !checkingSeller && isApprovedSeller
          ? FloatingActionButton.extended(
              onPressed: showAddProductDialog,
              backgroundColor: Colors.green.shade700,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text("Add Product",
                  style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }
}
