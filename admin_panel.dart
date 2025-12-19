import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dispute_management_page.dart'; // ADD THIS IMPORT

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage>
    with SingleTickerProviderStateMixin {
  final storage = const FlutterSecureStorage();
  late TabController _tabController;

  List<Map<String, dynamic>> pendingSellers = [];
  List<Map<String, dynamic>> allUsers = [];
  List<Map<String, dynamic>> allProducts = [];
  Map<String, dynamic> adminStats = {};
  bool loading = true;

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
    _tabController =
        TabController(length: 4, vsync: this); // CHANGED from 3 to 4
    fetchAdminData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchAdminData() async {
    setState(() => loading = true);
    await Future.wait([
      fetchPendingSellers(),
      fetchAllUsers(),
      fetchAllProducts(),
      fetchAdminStats(),
    ]);
    setState(() => loading = false);
  }

  Future<void> fetchAdminStats() async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/admin/stats'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          adminStats = data;
        });
      }
    } catch (e) {
      print('Error fetching admin stats: $e');
    }
  }

  Future<void> fetchPendingSellers() async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/admin/pending-sellers'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          pendingSellers = List<Map<String, dynamic>>.from(data['sellers']);
        });
      }
    } catch (e) {
      print('Error fetching pending sellers: $e');
    }
  }

  Future<void> fetchAllUsers() async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/admin/users'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          allUsers = List<Map<String, dynamic>>.from(data['users']);
        });
      }
    } catch (e) {
      print('Error fetching users: $e');
    }
  }

  Future<void> fetchAllProducts() async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/products'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          allProducts = List<Map<String, dynamic>>.from(data['products']);
        });
      }
    } catch (e) {
      print('Error fetching products: $e');
    }
  }

  Future<void> approveSeller(int userId) async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/admin/approve-seller/$userId'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seller approved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        fetchAdminData();
      } else {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Failed to approve seller'),
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

  Future<void> rejectSeller(int userId) async {
    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/admin/reject-seller/$userId'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seller request rejected'),
            backgroundColor: Colors.orange,
          ),
        );
        fetchAdminData();
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

  Future<void> deleteProduct(int productId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final token = await storage.read(key: 'jwt');
        final response = await http.delete(
          Uri.parse('$serverBaseUrl/api/admin/products/$productId'),
          headers: {"Authorization": "Bearer $token"},
        );

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          fetchAllProducts();
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

  Widget _buildStatsCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.white),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Panel', style: GoogleFonts.poppins()),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchAdminData,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.inventory), text: 'Products'),
            Tab(icon: Icon(Icons.gavel), text: 'Disputes'), // ADDED
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Dashboard Tab
                _buildDashboardTab(),

                // All Users Tab (with pending sellers at top)
                _buildEnhancedUsersTab(),

                // All Products Tab
                _buildAllProductsTab(),

                // Disputes Tab - ADDED
                const DisputeManagementPage(),
              ],
            ),
    );
  }

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: fetchAdminData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overview Statistics',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                _buildStatsCard(
                  'Total Users',
                  adminStats['total_users']?.toString() ?? '0',
                  Icons.people,
                  Colors.blue.shade700,
                ),
                _buildStatsCard(
                  'Pending Sellers',
                  adminStats['pending_sellers']?.toString() ?? '0',
                  Icons.pending,
                  Colors.orange.shade700,
                ),
                _buildStatsCard(
                  'Total Products',
                  adminStats['total_products']?.toString() ?? '0',
                  Icons.inventory,
                  Colors.green.shade700,
                ),
                _buildStatsCard(
                  'Total Orders',
                  adminStats['total_orders']?.toString() ?? '0',
                  Icons.shopping_cart,
                  Colors.purple.shade700,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Quick Actions',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildQuickActionButton(
              icon: Icons.refresh,
              label: 'Refresh All Data',
              color: Colors.blue,
              onTap: fetchAdminData,
            ),
            const SizedBox(height: 8),
            _buildQuickActionButton(
              icon: Icons.check_circle,
              label:
                  'View Pending Approvals (${adminStats['pending_sellers'] ?? 0})',
              color: Colors.orange,
              onTap: () => _tabController.animateTo(1), // Navigate to Users tab
            ),
            const SizedBox(height: 8),
            // ADDED: Quick access to disputes
            _buildQuickActionButton(
              icon: Icons.gavel,
              label: 'Manage Disputes',
              color: Colors.deepOrange,
              onTap: () =>
                  _tabController.animateTo(3), // Navigate to Disputes tab
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(label, style: GoogleFonts.poppins()),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _buildEnhancedUsersTab() {
    return RefreshIndicator(
      onRefresh: fetchAdminData,
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          // Pending Sellers Section
          if (pendingSellers.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.pending_actions, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Pending Seller Approvals (${pendingSellers.length})',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...pendingSellers.map((seller) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.orange.shade200, width: 2),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.shade700,
                      child: Text(
                        seller['username'][0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      seller['username'],
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(seller['email']),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'AWAITING APPROVAL',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          onPressed: () => approveSeller(seller['id']),
                          tooltip: 'Approve',
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () => rejectSeller(seller['id']),
                          tooltip: 'Reject',
                        ),
                      ],
                    ),
                  ),
                )),
            const Divider(height: 32, thickness: 2),
          ],

          // All Users Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.people, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'All Users (${allUsers.length})',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (allUsers.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No users found'),
              ),
            )
          else
            ...allUsers.map((user) {
              final isSeller = user['role'] == 'seller';
              final isApproved = user['is_approved'] == 1;
              final isPending = isSeller && !isApproved;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSeller && isApproved
                        ? Colors.green.shade700
                        : isPending
                            ? Colors.orange.shade700
                            : Colors.blue.shade700,
                    child: Text(
                      user['username'][0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    user['username'],
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user['email']),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              user['role'] ?? 'buyer',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white),
                            ),
                            backgroundColor: isSeller
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                            padding: EdgeInsets.zero,
                          ),
                          if (isSeller) ...[
                            const SizedBox(width: 8),
                            Chip(
                              label: Text(
                                isApproved ? 'Approved' : 'Pending',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white),
                              ),
                              backgroundColor:
                                  isApproved ? Colors.green : Colors.orange,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildAllProductsTab() {
    return allProducts.isEmpty
        ? const Center(child: Text('No products found'))
        : RefreshIndicator(
            onRefresh: fetchAdminData,
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: allProducts.length,
              itemBuilder: (context, index) {
                final product = allProducts[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: product['image_url'] != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              product['image_url'].toString().startsWith('http')
                                  ? product['image_url']
                                  : '$serverBaseUrl${product['image_url']}',
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.image),
                                );
                              },
                            ),
                          )
                        : Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey[300],
                            child: const Icon(Icons.image),
                          ),
                    title: Text(
                      product['name'],
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('₱${product['price']}'),
                        if (product['seller_name'] != null)
                          Text(
                            'Seller: ${product['seller_name']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => deleteProduct(product['id']),
                    ),
                  ),
                );
              },
            ),
          );
  }
}
