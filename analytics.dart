import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final storage = const FlutterSecureStorage();

  Map<String, dynamic> analytics = {
    '1day': {'sales': 0, 'revenue': 0.0, 'orders': 0},
    '7days': {'sales': 0, 'revenue': 0.0, 'orders': 0},
    '30days': {'sales': 0, 'revenue': 0.0, 'orders': 0},
    'alltime': {'sales': 0, 'revenue': 0.0, 'orders': 0},
  };
  String selectedPeriod = '7days';
  bool loadingAnalytics = false;
  int totalProducts = 0;
  int totalOrders = 0;

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
    fetchSellerAnalytics();
    fetchDashboardStats();
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
          totalProducts = data['total_products'] ?? 0;
        });
      }
    } catch (e) {
      print('Error fetching dashboard stats: $e');
    }
  }

  Future<void> fetchSellerAnalytics() async {
    try {
      setState(() => loadingAnalytics = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/seller/analytics'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          analytics = {
            '1day': {
              'sales': data['1day']?['total_sales'] ?? 0,
              'revenue': double.tryParse(
                      data['1day']?['total_revenue']?.toString() ?? '0') ??
                  0.0,
              'orders': data['1day']?['total_orders'] ?? 0,
            },
            '7days': {
              'sales': data['7days']?['total_sales'] ?? 0,
              'revenue': double.tryParse(
                      data['7days']?['total_revenue']?.toString() ?? '0') ??
                  0.0,
              'orders': data['7days']?['total_orders'] ?? 0,
            },
            '30days': {
              'sales': data['30days']?['total_sales'] ?? 0,
              'revenue': double.tryParse(
                      data['30days']?['total_revenue']?.toString() ?? '0') ??
                  0.0,
              'orders': data['30days']?['total_orders'] ?? 0,
            },
            'alltime': {
              'sales': data['alltime']?['total_sales'] ?? 0,
              'revenue': double.tryParse(
                      data['alltime']?['total_revenue']?.toString() ?? '0') ??
                  0.0,
              'orders': data['alltime']?['total_orders'] ?? 0,
            },
          };
          loadingAnalytics = false;
        });
      }
    } catch (e) {
      print('Error fetching analytics: $e');
      setState(() => loadingAnalytics = false);
    }
  }

  String _calculateAverageOrderValue() {
    final revenue = analytics[selectedPeriod]?['revenue'] ?? 0.0;
    final orders = analytics[selectedPeriod]?['orders'] ?? 0;

    if (orders == 0) return 'PHP 0.00';

    final average = revenue / orders;
    return 'PHP ${average.toStringAsFixed(2)}';
  }

  String _calculateConversionRate() {
    final orders = analytics['alltime']?['orders'] ?? 0;
    if (totalProducts == 0) return '0.0%';
    final rate = (orders / totalProducts) * 100;
    return '${rate.toStringAsFixed(1)}%';
  }

  String _calculateDailyAverage() {
    final revenue = analytics['30days']?['revenue'] ?? 0.0;
    final daily = revenue / 30;
    return 'PHP ${daily.toStringAsFixed(2)}';
  }

  String _calculateGrowthRate() {
    final revenue7 = analytics['7days']?['revenue'] ?? 0.0;
    final revenue30 = analytics['30days']?['revenue'] ?? 0.0;

    if (revenue30 == 0) return '0.0%';

    final avgDaily7 = revenue7 / 7;
    final avgDaily30 = revenue30 / 30;

    if (avgDaily30 == 0) return '0.0%';

    final growth = ((avgDaily7 - avgDaily30) / avgDaily30) * 100;
    final sign = growth >= 0 ? '+' : '';
    return '$sign${growth.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? Colors.blue.shade900 : Colors.blue.shade700,
        elevation: 0,
        title: Text(
          'Sales Analytics',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: fetchSellerAnalytics,
            tooltip: 'Refresh Analytics',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchSellerAnalytics,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                'Track Your Performance',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.blue.shade200 : Colors.blue.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Monitor your sales and revenue over time',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 30),

              // Period Selector
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withOpacity(0.3)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.blue.shade700 : Colors.blue.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    _buildPeriodChip('1D', '1day'),
                    _buildPeriodChip('7D', '7days'),
                    _buildPeriodChip('30D', '30days'),
                    _buildPeriodChip('All', 'alltime'),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Analytics Data
              if (loadingAnalytics)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Column(
                  children: [
                    // Revenue Card
                    _buildAnalyticsCard(
                      icon: Icons.attach_money,
                      label: 'Total Revenue',
                      value:
                          'PHP ${analytics[selectedPeriod]?['revenue']?.toStringAsFixed(2) ?? '0.00'}',
                      color: Colors.green.shade400,
                    ),
                    const SizedBox(height: 16),

                    // Orders & Sales Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildAnalyticsCard(
                            icon: Icons.shopping_cart,
                            label: 'Orders',
                            value:
                                '${analytics[selectedPeriod]?['orders'] ?? 0}',
                            color: Colors.orange.shade400,
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildAnalyticsCard(
                            icon: Icons.trending_up,
                            label: 'Items Sold',
                            value:
                                '${analytics[selectedPeriod]?['sales'] ?? 0}',
                            color: Colors.purple.shade400,
                            compact: true,
                          ),
                        ),
                      ],
                    ),

                    // Average Order Value
                    const SizedBox(height: 16),
                    _buildAnalyticsCard(
                      icon: Icons.calculate,
                      label: 'Avg Order Value',
                      value: _calculateAverageOrderValue(),
                      color: Colors.teal.shade400,
                    ),

                    const SizedBox(height: 30),

                    // Performance Indicators Section
                    Text(
                      'Performance Indicators',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.blue.shade200
                            : Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildPerformanceCard(
                      'Conversion Rate',
                      _calculateConversionRate(),
                      Icons.percent,
                      Colors.green,
                      'Orders / Total Products',
                    ),
                    const SizedBox(height: 12),
                    _buildPerformanceCard(
                      'Daily Average Revenue',
                      _calculateDailyAverage(),
                      Icons.calendar_today,
                      Colors.blue,
                      'Based on 30-day period',
                    ),
                    const SizedBox(height: 12),
                    _buildPerformanceCard(
                      'Growth Rate',
                      _calculateGrowthRate(),
                      Icons.trending_up,
                      Colors.purple,
                      '7-day vs 30-day comparison',
                    ),

                    const SizedBox(height: 30),

                    // All Periods Comparison
                    Text(
                      'Performance Overview',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.blue.shade200
                            : Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildDetailRow('Last 24 Hours', analytics['1day']),
                    const Divider(height: 32),
                    _buildDetailRow('Last 7 Days', analytics['7days']),
                    const Divider(height: 32),
                    _buildDetailRow('Last 30 Days', analytics['30days']),
                    const Divider(height: 32),
                    _buildDetailRow('All Time', analytics['alltime']),

                    const SizedBox(height: 30),

                    // Tips Section
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.orange.shade900.withOpacity(0.2)
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.orange.shade700
                              : Colors.orange.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lightbulb,
                                  color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Sales Tips',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '• Update your product descriptions regularly\n'
                            '• Respond quickly to customer messages\n'
                            '• Keep your stock levels updated\n'
                            '• Offer competitive pricing\n'
                            '• Use high-quality product images',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade700,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodChip(String label, String period) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = selectedPeriod == period;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            selectedPeriod = period;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? Colors.blue.shade800 : Colors.blue.shade700)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.blue.shade300 : Colors.blue.shade700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? color.withOpacity(0.4) : color.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 10 : 12),
            decoration: BoxDecoration(
              color: isDark ? color.withOpacity(0.25) : color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: compact ? 24 : 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: compact ? 20 : 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? color.withOpacity(0.4) : color.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? color.withOpacity(0.25) : color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String period, Map<String, dynamic>? data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          period,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildDetailMetric(
              'Revenue',
              'PHP ${data?['revenue']?.toStringAsFixed(2) ?? '0.00'}',
              Colors.green,
            ),
            _buildDetailMetric(
              'Orders',
              '${data?['orders'] ?? 0}',
              Colors.orange,
            ),
            _buildDetailMetric(
              'Items',
              '${data?['sales'] ?? 0}',
              Colors.purple,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailMetric(String label, String value, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
