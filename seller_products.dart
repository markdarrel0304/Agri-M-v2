import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'order_notifications_page.dart';

class SellerProductsPage extends StatefulWidget {
  const SellerProductsPage({super.key});

  @override
  State<SellerProductsPage> createState() => _SellerProductsPageState();
}

class _SellerProductsPageState extends State<SellerProductsPage> {
  final storage = const FlutterSecureStorage();
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> products = [];
  bool loading = true;
  int pendingOrdersCount = 0;

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
    fetchSellerProducts();
    fetchPendingOrdersCount();
  }

  // ✅ Helper function to safely get image URL
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
      print('❌ Error in _getImageUrl: $e');
      return null;
    }
  }

  Future<void> fetchSellerProducts() async {
    try {
      setState(() => loading = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/seller/products'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          products = List<Map<String, dynamic>>.from(data['products']);
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }
    } catch (e) {
      setState(() => loading = false);
      print('Error fetching products: $e');
    }
  }

  Future<void> fetchPendingOrdersCount() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/seller/pending-orders'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          pendingOrdersCount = (data['pending_orders'] as List).length;
        });
      }
    } catch (e) {
      print('Error fetching pending orders count: $e');
    }
  }

  // ✅ Add Product Function
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

      // Add quantity and unit
      if (quantity != null && quantity.isNotEmpty) {
        request.fields['stock'] = quantity;
      }
      if (unit != null && unit.isNotEmpty) {
        request.fields['unit'] = unit;
      }

      if (imageFile != null) {
        print('📸 Uploading image file...');
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
          await fetchSellerProducts();
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
            content: SingleChildScrollView(
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

                    // ✅ FIXED: Stock/Quantity with proper spacing
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
                          if (selectedImage != null)
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
                          ElevatedButton.icon(
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
                            ),
                          ),
                        ],
                      ),
                  ],
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

  Future<void> updateProduct(
    int productId,
    String name,
    String price,
    String description, {
    String? imageUrl,
    File? imageFile,
    String? category,
    String? quantity,
    String? unit,
  }) async {
    try {
      print('📤 Starting product update...');
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
                Text('Updating product...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('$serverBaseUrl/api/products/$productId'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['name'] = name;
      request.fields['price'] = price;
      if (description.isNotEmpty) {
        request.fields['description'] = description;
      }
      request.fields['category'] = category ?? 'General';

      // Add quantity and unit
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

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Product updated successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          await fetchSellerProducts();
        }
      } else {
        try {
          final data = json.decode(responseData);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ??
                    data['error'] ??
                    'Failed to update product'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to update product: $responseData'),
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
            content: Text('Error updating product: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void showEditProductDialog(Map<String, dynamic> product) {
    final nameController = TextEditingController(text: product['name']);
    final priceController =
        TextEditingController(text: product['price'].toString());
    final descriptionController =
        TextEditingController(text: product['description'] ?? '');
    final imageUrlController =
        TextEditingController(text: product['image_url'] ?? '');
    final quantityController =
        TextEditingController(text: product['stock']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    File? selectedImage;
    bool useImageFile = false;
    String selectedProductCategory = product['category'] ?? 'General';
    String selectedUnit = product['unit'] ?? 'Quantity';

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
                Icon(Icons.edit, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Text("Edit Product"),
              ],
            ),
            content: SingleChildScrollView(
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

                    // Stock/Quantity with proper spacing
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

                    // Show current image
                    if (product['image_url'] != null &&
                        selectedImage == null) ...[
                      Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _getImageUrl(product) ?? '',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.image, size: 40),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

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
                          if (selectedImage != null)
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
                          ElevatedButton.icon(
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
                                ? "Choose New Image"
                                : "Change Image"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                  ],
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
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.save),
                label: const Text("Update Product"),
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(context);
                    updateProduct(
                      product['id'],
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

  // ✅ Delete product function
  Future<void> deleteProduct(int productId, String productName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Text('Delete Product?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "$productName"?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
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
                      'This action cannot be undone',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w500,
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final token = await storage.read(key: 'jwt');
        final response = await http.delete(
          Uri.parse('$serverBaseUrl/api/products/$productId'),
          headers: {"Authorization": "Bearer $token"},
        );

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Product deleted successfully'),
                backgroundColor: Colors.green,
              ),
            );
            fetchSellerProducts();
          }
        } else {
          final data = json.decode(response.body);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['error'] ?? 'Failed to delete product'),
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

  // ✅ View product details dialog
  void showProductDetails(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;

        return AlertDialog(
          title: Text(product['name'].toString()),
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
                  if (product['stock'] != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.inventory_2,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 5),
                        Text(
                          'Stock: ${product['stock']} ${product['unit'] ?? ''}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (product['status'] != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: product['status'] == 'available'
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: product['status'] == 'available'
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                      child: Text(
                        'Status: ${product['status']}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: product['status'] == 'available'
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
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
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(
                        'Added: ${_formatDate(product['created_at']?.toString())}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Close"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.edit, size: 18),
              label: const Text("Edit"),
              onPressed: () {
                Navigator.pop(dialogContext);
                showEditProductDialog(product);
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.delete, size: 18),
              label: const Text("Delete"),
              onPressed: () {
                Navigator.pop(dialogContext);
                deleteProduct(product['id'], product['name']);
              },
            ),
          ],
        );
      },
    );
  }

  String _formatDate(String? timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      final date = DateTime.parse(timestamp);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Products"),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OrderNotificationsPage(),
                    ),
                  ).then((_) {
                    fetchPendingOrdersCount();
                  });
                },
              ),
              if (pendingOrdersCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
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
                      pendingOrdersCount > 99
                          ? '99+'
                          : pendingOrdersCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchSellerProducts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchSellerProducts,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : products.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2,
                            size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          "No products yet",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Tap the + button to add your first product",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: products.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.75,
                    ),
                    itemBuilder: (context, index) {
                      final product = products[index];

                      return GestureDetector(
                        onTap: () => showProductDetails(product),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(15),
                                      ),
                                      child: Builder(
                                        builder: (context) {
                                          final imageUrl =
                                              _getImageUrl(product);

                                          if (imageUrl == null) {
                                            return Container(
                                              color: Colors.grey[300],
                                              child: const Center(
                                                child:
                                                    Icon(Icons.image, size: 50),
                                              ),
                                            );
                                          }

                                          return Image.network(
                                            imageUrl,
                                            width: double.infinity,
                                            height: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.grey[300],
                                                child: const Icon(Icons.image,
                                                    size: 50),
                                              );
                                            },
                                            loadingBuilder: (context, child,
                                                loadingProgress) {
                                              if (loadingProgress == null)
                                                return child;
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
                                    // Delete button overlay
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.2),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: IconButton(
                                          icon: const Icon(Icons.delete,
                                              size: 20),
                                          color: Colors.white,
                                          padding: const EdgeInsets.all(8),
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            deleteProduct(
                                                product['id'], product['name']);
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Product Info
                              Expanded(
                                flex: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product['name'].toString(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const Spacer(),
                                      Text(
                                        "₱${product['price']}",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                      if (product['stock'] != null)
                                        Text(
                                          '${product['stock']} ${product['unit'] ?? ''}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showAddProductDialog,
        backgroundColor: Colors.green.shade700,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add Product", style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
