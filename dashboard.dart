import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

import 'settings.dart';
import 'login.dart';
import 'orders.dart';
import 'marketplace.dart';
import 'seller_products.dart';
import 'admin_panel.dart';
import 'chat_page.dart';
import 'admin_chat_page.dart';
import 'order_notifications_page.dart';
import 'order_notification_dialog.dart';
import 'notifications_page.dart';
import 'profile_management.dart';
import 'analytics.dart';
import 'payment_history_page.dart';
import 'blockchain_marketplace_page.dart';
import 'tutorial.dart';

class DashboardPage extends StatefulWidget {
  final String username;
  final bool isSeller;

  const DashboardPage({
    super.key,
    required this.username,
    this.isSeller = false,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  final storage = const FlutterSecureStorage();
  int unreadNotificationCount = 0;
  Timer? _orderCheckTimer;

  List<String> notifications = [];
  bool loadingNotifications = true;

  int totalOrders = 0;
  double totalRevenue = 0.0;
  int totalProducts = 0;
  bool isApprovedSeller = false;
  bool isAdmin = false;
  bool checkingAdmin = true;
  bool showTutorialIcon = false;
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
    WidgetsBinding.instance.addObserver(this);
    checkAdminStatus();
    fetchUnreadNotificationCount();
    _checkTutorialIcon(); // ✅ Add this

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _startOrderCheckTimer();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      print('📱 App resumed - refreshing dashboard');
      if (!isAdmin) {
        fetchAllDashboardData();
      }
      fetchUnreadNotificationCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orderCheckTimer?.cancel();
    super.dispose();
  }

  void _startOrderCheckTimer() {
    _orderCheckTimer?.cancel();

    _orderCheckTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (userRole == 'seller' && isApprovedSeller) {
        final newOrder = await _checkForNewOrders();
        if (newOrder != null && mounted) {
          showOrderNotificationDialog(
            context,
            newOrder,
            () {
              fetchAllDashboardData();
              fetchUnreadNotificationCount();
            },
            () {
              fetchAllDashboardData();
              fetchUnreadNotificationCount();
            },
          );
        }
      }
    });
  }

  Future<bool> _shouldShowNewBadge() async {
    const storage = FlutterSecureStorage();
    final firstLoginStr = await storage.read(key: 'first_login_date');

    if (firstLoginStr == null) return true;

    try {
      final firstLogin = DateTime.parse(firstLoginStr);
      final daysSinceFirstLogin = DateTime.now().difference(firstLogin).inDays;
      return daysSinceFirstLogin <= 7;
    } catch (e) {
      return false;
    }
  }

  Future<void> _checkTutorialIcon() async {
    final shouldShow = await shouldShowTutorialIcon();
    setState(() {
      showTutorialIcon = shouldShow;
    });
  }

  Future<Map<String, dynamic>?> _checkForNewOrders() async {
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

  Future<void> fetchUnreadNotificationCount() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/user/notifications/unread-count'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          unreadNotificationCount = data['unread_count'] ?? 0;
        });
      }
    } catch (e) {
      print('Error fetching unread count: $e');
    }
  }

  Future<void> checkAdminStatus() async {
    try {
      setState(() => checkingAdmin = true);

      final token = await storage.read(key: 'jwt');
      if (token == null) {
        setState(() {
          isAdmin = false;
          checkingAdmin = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/check-admin'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          isAdmin = data['is_admin'] == true || data['is_admin'] == 1;
          userRole = data['role'] ?? 'buyer';
          checkingAdmin = false;
        });

        await storage.write(key: 'is_admin', value: isAdmin.toString());
        await storage.write(key: 'role', value: userRole);

        if (isAdmin) {
          // Admin doesn't need buyer/seller data
        } else {
          fetchAllDashboardData();
        }
      } else {
        setState(() {
          isAdmin = false;
          checkingAdmin = false;
        });
        fetchAllDashboardData();
      }
    } catch (e) {
      setState(() {
        isAdmin = false;
        checkingAdmin = false;
      });
      fetchAllDashboardData();
    }
  }

  Future<void> fetchAllDashboardData() async {
    await Future.wait([
      fetchDashboardStats(),
      fetchNotifications(),
      checkSellerStatus(),
    ]);
  }

  Future<void> checkSellerStatus() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/is-approved-seller'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          isApprovedSeller = data['approved'] == true;
        });
        await storage.write(
            key: 'is_seller', value: isApprovedSeller.toString());
      }
    } catch (e) {
      setState(() => isApprovedSeller = false);
    }
  }

  Future<void> fetchDashboardStats() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/dashboard-stats'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          totalOrders = data['total_orders'] ?? 0;
          totalRevenue =
              double.tryParse(data['total_revenue']?.toString() ?? '0') ?? 0.0;
          totalProducts = data['total_products'] ?? 0;
        });

        print('📊 Dashboard Stats Updated:');
        print('  Orders: $totalOrders');
        print('  Revenue: $totalRevenue');
        print('  Products: $totalProducts');
      } else {
        print('❌ Dashboard stats failed: ${response.statusCode}');
        print('   Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Dashboard stats error: $e');
      setState(() {
        totalOrders = 0;
        totalRevenue = 0.0;
        totalProducts = 0;
      });
    }
  }

  Future<void> fetchNotifications() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/notifications'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          notifications = List<String>.from(data['notifications']);
          loadingNotifications = false;
        });
      }
    } catch (e) {
      setState(() {
        notifications = ["Unable to fetch notifications"];
        loadingNotifications = false;
      });
    }
  }

  Future<void> logout() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Logout"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _orderCheckTimer?.cancel();
      await storage.deleteAll();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (checkingAdmin) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text('Loading...', style: GoogleFonts.poppins()),
            ],
          ),
        ),
      );
    }

    if (isAdmin) {
      return _buildAdminDashboard(size);
    }

    return _buildUserDashboard(size);
  }

  Widget _buildAdminDashboard(Size size) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.purple.shade700,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, // ✅ Clear admin/security icon
                      size: 16,
                      color: Colors.purple.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'ADMIN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Admin Panel',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(
                    Icons.notifications_outlined), // ✅ Clear bell icon
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OrderNotificationsPage(),
                    ),
                  ).then((_) {
                    fetchUnreadNotificationCount();
                  });
                },
              ),
              if (unreadNotificationCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      unreadNotificationCount > 99
                          ? '99+'
                          : unreadNotificationCount.toString(),
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
            icon: const Icon(Icons.refresh_outlined,
                color: Colors.white), // ✅ Clear refresh icon
            onPressed: checkAdminStatus,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white), // ✅ Clear settings icon
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SettingsPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined,
                color: Colors.white), // ✅ Clear logout icon
            onPressed: logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FadeInDown(
              child: Text(
                'Admin Dashboard',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: size.width * 0.08,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade900,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FadeInUp(
              child: Text(
                'Welcome, ${widget.username}! 👨‍💼',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: size.width * 0.045,
                  color: Colors.purple.shade700,
                ),
              ),
            ),
            const SizedBox(height: 30),
            _buildAdminActionCard(
              title: 'Manage System',
              icon: Icons.dashboard_outlined, // ✅ Clear dashboard icon
              color: Colors.purple.shade700,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminPanelPage()),
                );
              },
            ),
            const SizedBox(height: 15),
            _buildAdminActionCard(
              title: 'User Management',
              icon: Icons.people_outline, // ✅ Clear users/people icon
              color: Colors.blue.shade700,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminPanelPage()),
                );
              },
            ),
            const SizedBox(height: 15),
            _buildAdminActionCard(
              title: 'Admin Chat',
              icon: Icons.forum_outlined, // ✅ Clear chat/forum icon
              color: Colors.green.shade700,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminChatPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios_outlined,
                  color: Colors.white), // ✅ Clear arrow
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserDashboard(Size size) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? Colors.green.shade900 : Colors.green.shade700,
        elevation: 0,
        title: Text(
          'Agri-M Dashboard',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        actions: [
          // ✅ Tutorial Icon (shows for 30 days)
          if (showTutorialIcon)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.school_outlined),
                  tooltip: 'Tutorial',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TutorialPage(
                          onComplete: () {
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    );
                  },
                ),
                // "NEW" badge for first 7 days
                FutureBuilder<bool>(
                  future: _shouldShowNewBadge(),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'NEW',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),

          // Notification Icon
          Stack(
            children: [
              IconButton(
                icon: const Icon(
                    Icons.notifications_outlined), // ✅ Clear notification bell
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsPage(),
                    ),
                  ).then((_) {
                    fetchUnreadNotificationCount();
                  });
                },
              ),
              if (unreadNotificationCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      unreadNotificationCount > 99
                          ? '99+'
                          : unreadNotificationCount.toString(),
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

          // Settings Icon
          IconButton(
            icon: const Icon(Icons.settings_outlined), // ✅ Clear settings gear
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchAllDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FadeInDown(
                child: Text(
                  'Dashboard',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: size.width * 0.08,
                    fontWeight: FontWeight.bold,
                    color:
                        isDark ? Colors.green.shade200 : Colors.green.shade900,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FadeInUp(
                child: Text(
                  'Welcome back, ${widget.username}! 👋',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: size.width * 0.045,
                    color:
                        isDark ? Colors.green.shade300 : Colors.green.shade700,
                  ),
                ),
              ),

              // ✅ OPTIONAL: Tutorial Card (shows for 30 days)
              if (showTutorialIcon) ...[
                const SizedBox(height: 20),
                _buildTutorialCard(),
              ],

              const SizedBox(height: 30),

              // Stats cards
              if (isApprovedSeller)
                Row(
                  children: [
                    Expanded(
                      child: _statsCard(
                        'Sales',
                        totalOrders.toString(),
                        Colors.blue,
                        Icons.trending_up_outlined, // ✅ Clear sales/growth icon
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statsCard(
                        'Revenue',
                        '₱${totalRevenue.toStringAsFixed(2)}',
                        Colors.green,
                        Icons.payments_outlined, // ✅ Clear money icon
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statsCard(
                        'Products',
                        totalProducts.toString(),
                        Colors.orange,
                        Icons.inventory_2_outlined, // ✅ Clear product/box icon
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _statsCard(
                        'Purchases',
                        totalOrders.toString(),
                        Colors.blue,
                        Icons
                            .shopping_bag_outlined, // ✅ Clear shopping bag icon
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statsCard(
                        'Products',
                        totalProducts.toString(),
                        Colors.orange,
                        Icons.inventory_2_outlined, // ✅ Clear product icon
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 30),

              // Action Buttons with CLEAN ICONS
              FadeInUp(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BlockchainMarketplacePage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.link_outlined,
                      size: 24), // ✅ Clear blockchain/chain icon
                  label: Text('Blockchain Features',
                      style: GoogleFonts.poppins(fontSize: 16)),
                  style: _buttonStyle(
                      isDark ? Colors.indigo.shade800 : Colors.indigo.shade700),
                ),
              ),
              const SizedBox(height: 15),

              FadeInLeft(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MarketplacePage()),
                    );

                    if (mounted) {
                      fetchAllDashboardData();
                      fetchUnreadNotificationCount();
                    }
                  },
                  icon: const Icon(Icons.storefront_outlined,
                      size: 24), // ✅ Clear store/shop icon
                  label: Text('Browse Marketplace',
                      style: GoogleFonts.poppins(fontSize: 16)),
                  style: _buttonStyle(
                      isDark ? Colors.green.shade800 : Colors.green.shade700),
                ),
              ),
              const SizedBox(height: 15),

              FadeInRight(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrdersPage()),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_outlined,
                      size: 24), // ✅ Clear receipt/order icon
                  label: Text('My Orders',
                      style: GoogleFonts.poppins(fontSize: 16)),
                  style: _buttonStyle(
                      isDark ? Colors.orange.shade800 : Colors.orange.shade700),
                ),
              ),
              const SizedBox(height: 15),

              FadeInLeft(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatPage()),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline,
                      size: 24), // ✅ Clear chat bubble icon
                  label: Text('Messages',
                      style: GoogleFonts.poppins(fontSize: 16)),
                  style: _buttonStyle(
                      isDark ? Colors.blue.shade800 : Colors.blue.shade700),
                ),
              ),
              const SizedBox(height: 15),

              FadeInRight(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PaymentHistoryPage()),
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet_outlined,
                      size: 24), // ✅ Clear wallet/payment icon
                  label: Text('Payment History',
                      style: GoogleFonts.poppins(fontSize: 16)),
                  style: _buttonStyle(
                      isDark ? Colors.indigo.shade800 : Colors.indigo.shade700),
                ),
              ),
              const SizedBox(height: 15),

              FadeInLeft(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfileManagementPage()),
                    );
                  },
                  icon: const Icon(Icons.person_outline,
                      size: 24), // ✅ Clear person/profile icon
                  label: Text('My Profile',
                      style: GoogleFonts.poppins(fontSize: 16)),
                  style: _buttonStyle(
                      isDark ? Colors.purple.shade800 : Colors.purple.shade700),
                ),
              ),

              if (isApprovedSeller) ...[
                const SizedBox(height: 15),
                FadeInUp(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SellerProductsPage()),
                      );
                    },
                    icon: const Icon(Icons.inventory_outlined,
                        size: 24), // ✅ Clear inventory/warehouse icon
                    label: Text('Manage Products',
                        style: GoogleFonts.poppins(fontSize: 16)),
                    style: _buttonStyle(
                        isDark ? Colors.teal.shade800 : Colors.teal.shade700),
                  ),
                ),
                const SizedBox(height: 15),
                FadeInUp(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AnalyticsPage()),
                      );
                    },
                    icon: const Icon(Icons.bar_chart_outlined,
                        size: 24), // ✅ Clear analytics/chart icon
                    label: Text('View Analytics',
                        style: GoogleFonts.poppins(fontSize: 16)),
                    style: _buttonStyle(isDark
                        ? Colors.indigo.shade800
                        : Colors.indigo.shade700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

// ✅ Add this method to build the tutorial card
  Widget _buildTutorialCard() {
    return FadeInDown(
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade700, Colors.blue.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.school,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New to Agri-M?',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Take a quick tour to learn the basics',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TutorialPage(
                        onComplete: () {
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _statsCard(String title, String value, Color color, IconData icon) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: isDark ? color.withOpacity(0.2) : color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 110),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isDark ? color : Colors.white,
              size: 24,
            ),
            const SizedBox(height: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? color : Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? color.withOpacity(0.8) : Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
