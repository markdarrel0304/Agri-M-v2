import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class BlockchainMarketplacePage extends StatefulWidget {
  const BlockchainMarketplacePage({super.key});

  @override
  State<BlockchainMarketplacePage> createState() =>
      _BlockchainMarketplacePageState();
}

class _BlockchainMarketplacePageState extends State<BlockchainMarketplacePage>
    with SingleTickerProviderStateMixin {
  final storage = const FlutterSecureStorage();
  late TabController _tabController;

  List<Map<String, dynamic>> blockchain = [];
  List<Map<String, dynamic>> verifiedProducts = [];
  // Changed: Now storing supply chain per product
  Map<int, List<Map<String, dynamic>>> productSupplyChains = {};
  List<Map<String, dynamic>> recentTransactions = [];
  bool loading = true;
  bool validatingChain = false;

  int totalBlocks = 0;
  int totalTransactions = 0;
  String chainStatus = 'Valid';
  double chainIntegrity = 100.0;
  String? currentUserId;

  String get serverUrl =>
      Platform.isAndroid ? "http://10.0.2.2:8881" : "http://localhost:8881";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadCurrentUser();
    _initializeBlockchain();
    _loadBlockchainData();
    _loadBlockchainTransactions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token != null) {
        final response = await http.get(
          Uri.parse('$serverUrl/api/me'),
          headers: {"Authorization": "Bearer $token"},
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          setState(() {
            currentUserId = data['user']['id'].toString();
          });
        }
      }
    } catch (e) {
      print('Error loading current user: $e');
    }
  }

  Future<void> _loadBlockchainData() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverUrl/api/products'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final products = List<Map<String, dynamic>>.from(data['products']);

        setState(() {
          verifiedProducts = products
              .map((p) => {
                    'id': p['id'],
                    'name': p['name'],
                    'seller': p['seller_name'] ?? 'Unknown',
                    'sellerId': p['seller_id'],
                    'price': double.tryParse(p['price'].toString()) ?? 0.0,
                    'stock': p['stock'] ?? 0,
                    'blockchainId': 'BLK${p['id'].toString().padLeft(6, '0')}',
                    'verified': true,
                    'certifications': ['Verified Seller', 'Quality Checked'],
                    'supplyChainStages': 0,
                    'category': p['category'] ?? 'General',
                    'image_url': p['image_url'],
                  })
              .toList();
        });

        // ✅ Initialize empty supply chains only
        for (var product in verifiedProducts) {
          productSupplyChains[product['id']] = [];
        }
      }
    } catch (e) {
      print('Error loading blockchain data: $e');
    }
  }

  Future<void> _loadBlockchainTransactions() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverUrl/api/blockchain/transactions'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final transactions =
            List<Map<String, dynamic>>.from(data['transactions']);

        // Clear existing blockchain (keep genesis block)
        setState(() {
          blockchain = [blockchain.first]; // Keep genesis block
        });

        // Add real transactions to blockchain
        for (var tx in transactions) {
          _addBlockToChain({
            'type': tx['type'] == 'order' ? 'purchase' : tx['type'],
            'product': tx['product'],
            'buyer': tx['buyer'],
            'seller': tx['seller'],
            'price': tx['price'],
            'quantity': tx['quantity'],
            'status': tx['status'],
          });
        }
      }
    } catch (e) {
      print('Error loading blockchain transactions: $e');
    }
  }

  void _initializeBlockchain() {
    setState(() {
      blockchain = [
        {
          'index': 0,
          'timestamp': DateTime.now()
              .subtract(const Duration(days: 30))
              .millisecondsSinceEpoch,
          'data': {'type': 'Genesis Block'},
          'hash': _calculateHash(
              '0', 'Genesis Block', DateTime.now().millisecondsSinceEpoch),
          'previousHash': '0',
          'nonce': 0,
          'difficulty': 2,
        }
      ];

      loading = false;
    });
  }

  void _addBlockToChain(Map<String, dynamic> data) {
    final newIndex = blockchain.length;
    final previousHash =
        blockchain.isNotEmpty ? blockchain.last['hash'].toString() : '0';
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    int nonce = 0;
    String hash;
    const difficulty = 2;
    final target = '0' * difficulty;

    do {
      hash = _calculateHashWithNonce(
        newIndex.toString(),
        json.encode(data),
        timestamp,
        previousHash,
        nonce,
      );
      nonce++;
    } while (!hash.startsWith(target));

    final newBlock = {
      'index': newIndex,
      'timestamp': timestamp,
      'data': data,
      'hash': hash,
      'previousHash': previousHash,
      'nonce': nonce,
      'difficulty': difficulty,
    };

    setState(() {
      blockchain.add(newBlock);
      totalBlocks = blockchain.length;
      totalTransactions =
          blockchain.where((b) => b['data']['type'] != 'Genesis Block').length;

      if (recentTransactions.length >= 10) {
        recentTransactions.removeAt(0);
      }
      recentTransactions.add(newBlock);
    });
  }

  String _calculateHash(String index, String data, int timestamp) {
    final input = '$index$data$timestamp';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  String _calculateHashWithNonce(
    String index,
    String data,
    int timestamp,
    String previousHash,
    int nonce,
  ) {
    final input = '$index$data$timestamp$previousHash$nonce';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _validateBlockchain() async {
    setState(() {
      validatingChain = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    bool isValid = true;
    int validBlocks = 0;

    for (int i = 1; i < blockchain.length; i++) {
      final currentBlock = blockchain[i];
      final previousBlock = blockchain[i - 1];

      if (currentBlock['previousHash'] != previousBlock['hash']) {
        isValid = false;
        break;
      }

      final calculatedHash = _calculateHashWithNonce(
        currentBlock['index'].toString(),
        json.encode(currentBlock['data']),
        currentBlock['timestamp'],
        currentBlock['previousHash'],
        currentBlock['nonce'],
      );

      if (calculatedHash != currentBlock['hash']) {
        isValid = false;
        break;
      }

      validBlocks++;
    }

    setState(() {
      chainStatus = isValid ? 'Valid ✓' : 'Invalid ✗';
      chainIntegrity = validBlocks / (blockchain.length - 1) * 100;
      validatingChain = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isValid
                ? '✓ Blockchain validated successfully!'
                : '✗ Blockchain validation failed!',
          ),
          backgroundColor: isValid ? Colors.green : Colors.red,
        ),
      );
    }
  }

  // NEW: Add supply chain stage for a product
  void _addSupplyChainStage(Map<String, dynamic> product) {
    final productId = product['id'];
    final stages = productSupplyChains[productId] ?? [];

    showDialog(
      context: context,
      builder: (context) => _AddSupplyChainStageDialog(
        productName: product['name'],
        currentStageCount: stages.length,
        onAdd: (stageData) {
          final newStage = {
            'stage': stages.length + 1,
            'name': stageData['name'],
            'date': stageData['date'],
            'location': stageData['location'],
            'verified': true,
            'hash': _calculateHash(
              productId.toString(),
              stageData['name'],
              DateTime.now().millisecondsSinceEpoch,
            ),
            'notes': stageData['notes'],
            'addedBy': currentUserId,
          };

          setState(() {
            productSupplyChains[productId] = [...stages, newStage];

            // Update product's stage count
            final prodIndex =
                verifiedProducts.indexWhere((p) => p['id'] == productId);
            if (prodIndex != -1) {
              verifiedProducts[prodIndex]['supplyChainStages'] =
                  stages.length + 1;
            }
          });

          // Add to blockchain
          _addBlockToChain({
            'type': 'supply_chain_update',
            'product': product['name'],
            'productId': productId,
            'stage': newStage['name'],
            'location': newStage['location'],
            'date': newStage['date'],
          });

          Navigator.pop(context);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Supply chain stage added to blockchain!'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? Colors.green.shade900 : Colors.green.shade700,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Blockchain Marketplace',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: validatingChain
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Icon(Icons.verified_user),
            onPressed: validatingChain ? null : _validateBlockchain,
            tooltip: 'Validate Blockchain',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              _loadBlockchainData();
              setState(() {
                loading = true;
              });
              Future.delayed(Duration(seconds: 1), () {
                setState(() {
                  loading = false;
                });
              });
            },
            tooltip: 'Refresh Data',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.inventory), text: 'Products'),
            Tab(icon: Icon(Icons.timeline), text: 'Supply Chain'),
            Tab(icon: Icon(Icons.shield), text: 'Blockchain'),
            Tab(icon: Icon(Icons.history), text: 'Transactions'),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(isDark),
                _buildProductsTab(isDark),
                _buildSupplyChainTab(isDark),
                _buildBlockchainTab(isDark),
                _buildTransactionsTab(isDark),
              ],
            ),
    );
  }

  Widget _buildOverviewTab(bool isDark) {
    final totalSupplyChainStages = productSupplyChains.values
        .fold<int>(0, (sum, stages) => sum + stages.length);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: chainStatus.contains('Valid')
                    ? [Colors.green.shade400, Colors.green.shade600]
                    : [Colors.red.shade400, Colors.red.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  chainStatus.contains('Valid')
                      ? Icons.verified
                      : Icons.warning,
                  size: 48,
                  color: Colors.white,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Blockchain Status',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        chainStatus,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: chainIntegrity / 100,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Integrity: ${chainIntegrity.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
              _buildStatCard(
                'Total Blocks',
                totalBlocks.toString(),
                Icons.grid_view,
                Colors.blue,
                isDark,
              ),
              _buildStatCard(
                'Verified Products',
                verifiedProducts.length.toString(),
                Icons.verified,
                Colors.green,
                isDark,
              ),
              _buildStatCard(
                'Transactions',
                totalTransactions.toString(),
                Icons.swap_horiz,
                Colors.purple,
                isDark,
              ),
              _buildStatCard(
                'Supply Chain Stages',
                totalSupplyChainStages.toString(),
                Icons.timeline,
                Colors.orange,
                isDark,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Blockchain Features',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            'Immutable Records',
            'All transactions are permanently recorded and cannot be altered',
            Icons.lock,
            Colors.blue,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            'Smart Contracts',
            'Automated escrow and payment release with zero intermediaries',
            Icons.auto_awesome,
            Colors.purple,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            'Supply Chain Tracking',
            'Track products from farm to table with cryptographic verification',
            Icons.timeline,
            Colors.green,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            'Decentralized Trust',
            'No single point of failure - distributed consensus mechanism',
            Icons.verified_user,
            Colors.orange,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildProductsTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadBlockchainData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: verifiedProducts.length,
        itemBuilder: (context, index) {
          final product = verifiedProducts[index];
          final productId = product['id'];
          final supplyChainStages = productSupplyChains[productId]?.length ?? 0;
          final canAddStages = product['sellerId'].toString() == currentUserId;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product['name'],
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (product['verified'])
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified,
                                color: Colors.green.shade700,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                      SizedBox(width: 4),
                      Text(
                        'Seller: ${product['seller']}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₱${product['price'].toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Supply Chain Progress Indicator
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: supplyChainStages > 0
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: supplyChainStages > 0
                            ? Colors.blue.shade200
                            : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timeline,
                          size: 16,
                          color: supplyChainStages > 0
                              ? Colors.blue.shade700
                              : Colors.orange.shade700,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            supplyChainStages > 0
                                ? 'Supply Chain: $supplyChainStages stages tracked'
                                : 'No supply chain data yet',
                            style: TextStyle(
                              fontSize: 12,
                              color: supplyChainStages > 0
                                  ? Colors.blue.shade700
                                  : Colors.orange.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: supplyChainStages > 0
                              ? () => _showSupplyChainDialog(product)
                              : null,
                          icon: const Icon(Icons.timeline, size: 18),
                          label: Text(supplyChainStages > 0
                              ? 'View Track'
                              : 'No Tracking'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green.shade700,
                          ),
                        ),
                      ),
                      if (canAddStages) ...[
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _addSupplyChainStage(product),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Stage'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildSupplyChainTab(bool isDark) {
    // Show all products with their supply chains
    final productsWithSupplyChain = verifiedProducts
        .where((p) => (productSupplyChains[p['id']]?.length ?? 0) > 0)
        .toList();

    if (productsWithSupplyChain.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timeline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: 16),
            Text(
              'No supply chain data yet',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Sellers can add supply chain stages\nto their products',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: productsWithSupplyChain.length,
      itemBuilder: (context, index) {
        final product = productsWithSupplyChain[index];
        final productId = product['id'];
        final stages = productSupplyChains[productId] ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ExpansionTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.inventory, color: Colors.green.shade700),
            ),
            title: Text(
              product['name'],
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${stages.length} supply chain stages'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: stages.asMap().entries.map((entry) {
                    final stageIndex = entry.key;
                    final stage = entry.value;
                    final isLast = stageIndex == stages.length - 1;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.green.shade700,
                                size: 24,
                              ),
                            ),
                            if (!isLast)
                              Container(
                                width: 2,
                                height: 60,
                                color: Colors.green.shade300,
                              ),
                          ],
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.only(bottom: 16),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stage ${stage['stage']}: ${stage['name']}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.location_on,
                                        size: 14, color: Colors.grey.shade600),
                                    SizedBox(width: 4),
                                    Text(
                                      stage['location'],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today,
                                        size: 14, color: Colors.grey.shade600),
                                    SizedBox(width: 4),
                                    Text(
                                      stage['date'],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (stage['notes'] != null &&
                                    stage['notes'].isNotEmpty) ...[
                                  SizedBox(height: 4),
                                  Text(
                                    stage['notes'],
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBlockchainTab(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: blockchain.length,
      itemBuilder: (context, index) {
        final block = blockchain[blockchain.length - 1 - index];
        final timestamp =
            DateTime.fromMillisecondsSinceEpoch(block['timestamp']);

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.grid_view,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Block #${block['index']}',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${timestamp.day}/${timestamp.month}/${timestamp.year}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildBlockDetailRow('Type', block['data']['type']),
                _buildBlockDetailRow('Hash', block['hash']),
                _buildBlockDetailRow('Previous Hash', block['previousHash']),
                _buildBlockDetailRow('Nonce', block['nonce'].toString()),
                _buildBlockDetailRow(
                    'Difficulty', block['difficulty'].toString()),
                if (block['data']['product'] != null) ...[
                  const Divider(height: 24),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.receipt_long,
                                size: 18, color: Colors.green.shade700),
                            SizedBox(width: 8),
                            Text(
                              'Transaction Data',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (block['data']['product'] != null)
                          _buildBlockDetailRow(
                              'Product', block['data']['product']),
                        if (block['data']['seller'] != null)
                          _buildBlockDetailRow(
                              'Seller', block['data']['seller']),
                        if (block['data']['stage'] != null)
                          _buildBlockDetailRow('Stage', block['data']['stage']),
                        if (block['data']['location'] != null)
                          _buildBlockDetailRow(
                              'Location', block['data']['location']),
                        if (block['data']['buyer'] != null)
                          _buildBlockDetailRow('Buyer', block['data']['buyer']),
                        if (block['data']['price'] != null)
                          _buildBlockDetailRow(
                              'Price', '₱${block['data']['price']}'),
                        if (block['data']['quantity'] != null)
                          _buildBlockDetailRow(
                              'Quantity', block['data']['quantity'].toString()),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactionsTab(bool isDark) {
    if (recentTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: 16),
            Text(
              'No recent transactions',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: recentTransactions.length,
      itemBuilder: (context, index) {
        final tx = recentTransactions[recentTransactions.length - 1 - index];
        final timestamp = DateTime.fromMillisecondsSinceEpoch(tx['timestamp']);
        final data = tx['data'];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getTransactionColor(data['type']),
              child: Icon(
                _getTransactionIcon(data['type']),
                color: Colors.white,
                size: 20,
              ),
            ),
            title: Text(
              data['type'].toString().replaceAll('_', ' ').toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                if (data['product'] != null)
                  Text('Product: ${data['product']}',
                      style: TextStyle(fontSize: 12)),
                if (data['stage'] != null)
                  Text('Stage: ${data['stage']}',
                      style: TextStyle(fontSize: 12)),
                Text(
                  '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Block #${tx['index']}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                if (data['price'] != null)
                  Text(
                    '₱${data['price']}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
              ],
            ),
            onTap: () => _showBlockDetails(tx),
          ),
        );
      },
    );
  }

  Color _getTransactionColor(String type) {
    switch (type) {
      case 'product_listing':
        return Colors.blue;
      case 'purchase':
        return Colors.green;
      case 'payment':
        return Colors.orange;
      case 'supply_chain_update':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getTransactionIcon(String type) {
    switch (type) {
      case 'product_listing':
        return Icons.add_shopping_cart;
      case 'purchase':
        return Icons.shopping_bag;
      case 'payment':
        return Icons.payment;
      case 'supply_chain_update':
        return Icons.timeline;
      default:
        return Icons.receipt;
    }
  }

  void _showBlockDetails(Map<String, dynamic> block) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(block['timestamp']);
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    final String prettyJson = encoder.convert(block['data']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.grid_view, color: Colors.blue.shade700),
            SizedBox(width: 8),
            Text('Block #${block['index']}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Timestamp',
                  '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute}'),
              _buildDetailRow('Hash', block['hash']),
              _buildDetailRow('Previous Hash', block['previousHash']),
              _buildDetailRow('Nonce', block['nonce'].toString()),
              _buildDetailRow('Difficulty', block['difficulty'].toString()),
              Divider(height: 24),
              Text('Data:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  prettyJson,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  void _showSupplyChainDialog(Map<String, dynamic> product) {
    final productId = product['id'];
    final stages = productSupplyChains[productId] ?? [];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.timeline, color: Colors.green.shade700),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Supply Chain: ${product['name']}',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Expanded(
                child: stages.isEmpty
                    ? Center(
                        child: Text(
                          'No supply chain stages yet',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.builder(
                        itemCount: stages.length,
                        itemBuilder: (context, index) {
                          final stage = stages[index];
                          final isLast = index == stages.length - 1;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check_circle,
                                      color: Colors.green.shade700,
                                      size: 24,
                                    ),
                                  ),
                                  if (!isLast)
                                    Container(
                                      width: 2,
                                      height: 60,
                                      color: Colors.green.shade300,
                                    ),
                                ],
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(bottom: 16),
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Stage ${stage['stage']}: ${stage['name']}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '📍 ${stage['location']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        '📅 ${stage['date']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      if (stage['notes'] != null &&
                                          stage['notes'].isNotEmpty) ...[
                                        SizedBox(height: 4),
                                        Text(
                                          stage['notes'],
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                      SizedBox(height: 6),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Hash: ${stage['hash']}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontFamily: 'monospace',
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color, bool isDark) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(String title, String description, IconData icon,
      Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
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

  Widget _buildBlockDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// NEW: Dialog for adding supply chain stages
class _AddSupplyChainStageDialog extends StatefulWidget {
  final String productName;
  final int currentStageCount;
  final Function(Map<String, dynamic>) onAdd;

  const _AddSupplyChainStageDialog({
    required this.productName,
    required this.currentStageCount,
    required this.onAdd,
  });

  @override
  State<_AddSupplyChainStageDialog> createState() =>
      _AddSupplyChainStageDialogState();
}

class _AddSupplyChainStageDialogState
    extends State<_AddSupplyChainStageDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  // Common supply chain stage names
  final List<String> _stagePresets = [
    'Planting',
    'Growing',
    'Harvesting',
    'Processing',
    'Quality Check',
    'Packaging',
    'Storage',
    'Transportation',
    'Distribution',
    'Retail',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_circle, color: Colors.green.shade700),
              SizedBox(width: 8),
              Expanded(child: Text('Add Supply Chain Stage')),
            ],
          ),
          SizedBox(height: 8),
          Text(
            widget.productName,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stage ${widget.currentStageCount + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              SizedBox(height: 16),

              // Quick presets
              Text(
                'Quick Select:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _stagePresets.map((preset) {
                  return ActionChip(
                    label: Text(preset, style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      _nameController.text = preset;
                    },
                    backgroundColor: Colors.green.shade50,
                  );
                }).toList(),
              ),

              SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Stage Name *',
                  hintText: 'e.g., Harvesting',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a stage name';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16),

              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Location *',
                  hintText: 'e.g., Nueva Ecija',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a location';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16),

              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),

              SizedBox(height: 16),

              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Additional details...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              widget.onAdd({
                'name': _nameController.text,
                'location': _locationController.text,
                'date':
                    '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                'notes': _notesController.text,
              });
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
          ),
          child: Text('Add to Blockchain'),
        ),
      ],
    );
  }
}
