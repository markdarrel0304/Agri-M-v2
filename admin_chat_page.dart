import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class AdminChatPage extends StatefulWidget {
  const AdminChatPage({super.key});

  @override
  State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> {
  final storage = const FlutterSecureStorage();
  final messageController = TextEditingController();
  final searchController = TextEditingController();
  final scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> allConversations = [];
  List<Map<String, dynamic>> filteredConversations = [];
  bool loading = true;
  String? selectedConvId;
  String? selectedUser1;
  String? selectedUser2;
  Timer? refreshTimer;
  String filterStatus = 'all';
  bool showChatOnMobile = false; // NEW: Track mobile view state

  String get serverUrl =>
      Platform.isAndroid ? "http://10.0.2.2:8881" : "http://localhost:8881";

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    messageController.dispose();
    searchController.dispose();
    scrollController.dispose();
    refreshTimer?.cancel();
    super.dispose();
  }

  void _init() {
    _loadConversations();
    searchController.addListener(_filterConversations);
    refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _loadConversations();
        if (selectedConvId != null) {
          _loadMessages(selectedConvId!, silent: true);
        }
      }
    });
  }

  void _filterConversations() {
    setState(() {
      filteredConversations = allConversations.where((conv) {
        final search = searchController.text.toLowerCase();
        final matchesSearch = search.isEmpty ||
            conv['user1_name'].toString().toLowerCase().contains(search) ||
            conv['user2_name'].toString().toLowerCase().contains(search);
        final matchesFilter = filterStatus == 'all' ||
            (filterStatus == 'active' && conv['message_count'] > 0) ||
            (filterStatus == 'archived' && conv['message_count'] == 0);
        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  Future<void> _loadConversations() async {
    try {
      if (allConversations.isEmpty) setState(() => loading = true);

      final token = await storage.read(key: 'jwt');
      if (token == null) {
        print('❌ No JWT token found');
        setState(() => loading = false);
        return;
      }

      print('🔄 Loading conversations...');
      final response = await http.get(
        Uri.parse('$serverUrl/api/admin/all-conversations'),
        headers: {"Authorization": "Bearer $token"},
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Raw response: ${response.body}'); // Add this line

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Loaded ${data['conversations'].length} conversations');

        // Print first conversation for debugging
        if (data['conversations'].isNotEmpty) {
          print('🔍 First conversation sample:');
          print(json.encode(data['conversations'][0]));
        }

        setState(() {
          allConversations =
              List<Map<String, dynamic>>.from(data['conversations']);
          _filterConversations();
          loading = false;
        });
      } else {
        print('❌ Error: ${response.body}');
        setState(() => loading = false);
      }
    } catch (e) {
      print('❌ Exception: $e');
      setState(() => loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading conversations: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadMessages(String convId, {bool silent = false}) async {
    try {
      if (!silent) {
        print('🔄 Loading messages for conversation: $convId');
        setState(() => loading = true);
      }

      final token = await storage.read(key: 'jwt');
      if (token == null) {
        print('❌ No JWT token found');
        if (!silent) setState(() => loading = false);
        return;
      }

      // ✅ CHANGE THIS TO ADMIN ENDPOINT
      print('📡 Calling ADMIN API: $serverUrl/api/admin/messages/$convId');
      final response = await http.get(
        Uri.parse('$serverUrl/api/admin/messages/$convId'), // Changed endpoint
        headers: {"Authorization": "Bearer $token"},
      );

      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('📊 Response data keys: ${data.keys}');

        // Check if 'messages' key exists
        if (data['messages'] == null) {
          print('⚠️ No "messages" key in response');
          print('Full response: ${json.encode(data)}');
        }

        final newMessages =
            List<Map<String, dynamic>>.from(data['messages'] ?? []);
        print('✅ Loaded ${newMessages.length} messages');

        setState(() {
          messages = newMessages;
          if (!silent) loading = false;
        });

        // ... rest of your code
      } else {
        print('❌ Error response: ${response.body}');
        if (!silent) setState(() => loading = false);

        // Try the regular endpoint as fallback
        if (response.statusCode == 403 || response.statusCode == 404) {
          print('🔄 Trying regular messages endpoint...');
          await _loadMessagesRegular(convId, silent: silent);
        }
      }
    } catch (e) {
      print('❌ Exception loading messages: $e');
      if (!silent)
        setState(() {
          loading = false;
          messages = [];
        });
    }
  }

// Fallback method for regular endpoint
  Future<void> _loadMessagesRegular(String convId,
      {bool silent = false}) async {
    try {
      final token = await storage.read(key: 'jwt');

      final response = await http.get(
        Uri.parse('$serverUrl/api/messages/$convId'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newMessages =
            List<Map<String, dynamic>>.from(data['messages'] ?? []);

        setState(() {
          messages = newMessages;
          if (!silent) loading = false;
        });
      }
    } catch (e) {
      print('❌ Fallback also failed: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (messageController.text.trim().isEmpty || selectedConvId == null) return;

    final token = await storage.read(key: 'jwt');
    final text = messageController.text.trim();
    messageController.clear();

    final response = await http.post(
      Uri.parse('$serverUrl/api/messages'),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: json.encode({
        'conversation_id': selectedConvId,
        'message': '[ADMIN] $text',
      }),
    );

    if (response.statusCode == 201) {
      _loadMessages(selectedConvId!);
      _loadConversations();
    }
  }

  Future<void> _deleteConversation(String convId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: const Text('This will permanently delete all messages.'),
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
      final token = await storage.read(key: 'jwt');
      final response = await http.delete(
        Uri.parse('$serverUrl/api/admin/conversations/$convId'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        if (selectedConvId == convId) {
          setState(() {
            selectedConvId = null;
            messages = [];
            showChatOnMobile = false; // Return to list view
          });
        }
        _loadConversations();
      }
    }
  }

  Future<void> _unreportConversation(String convId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dismiss Report?'),
        content: const Text('This will mark the conversation as not reported.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverUrl/api/admin/conversations/$convId/unreport'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        _loadConversations();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Report dismissed'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          isMobile && showChatOnMobile
              ? '$selectedUser1 ↔ $selectedUser2'
              : 'Admin Chat Monitor',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
        leading: isMobile && showChatOnMobile
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    showChatOnMobile = false;
                    selectedConvId = null;
                    messages = [];
                  });
                },
              )
            : null,
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
      body: isMobile
          ? (showChatOnMobile ? _buildChatArea() : _buildSidebar())
          : Row(
              children: [
                SizedBox(width: 350, child: _buildSidebar()),
                Expanded(child: _buildChatArea()),
              ],
            ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.purple.shade700,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.admin_panel_settings, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'All Conversations',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        filteredConversations.length.toString(),
                        style: TextStyle(
                          color: Colors.purple.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search users...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    prefixIcon: Icon(Icons.search,
                        color: Colors.white.withOpacity(0.7)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Active', 'active'),
                const SizedBox(width: 8),
                _buildFilterChip('Empty', 'archived'),
              ],
            ),
          ),
          Expanded(
            child: loading && allConversations.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : filteredConversations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('No conversations found',
                                style: TextStyle(color: Colors.grey.shade600)),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _loadConversations,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple.shade700,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredConversations.length,
                        itemBuilder: (context, index) {
                          final conv = filteredConversations[index];
                          final isSelected =
                              selectedConvId == conv['id'].toString();
                          final isReported = conv['is_reported'] == 1;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                selectedConvId = conv['id'].toString();
                                selectedUser1 = conv['user1_name'];
                                selectedUser2 = conv['user2_name'];
                                showChatOnMobile = true; // Show chat on mobile
                              });
                              _loadMessages(selectedConvId!);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isReported
                                    ? Colors.red.shade50
                                    : (isSelected
                                        ? Colors.purple.shade50
                                        : Colors.transparent),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isReported
                                      ? Colors.red.shade700
                                      : (isSelected
                                          ? Colors.purple.shade700
                                          : Colors.transparent),
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Stack(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor:
                                                Colors.purple.shade700,
                                            child: Text(
                                              (conv['user1_name'] ?? 'U')[0]
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          if (isReported)
                                            Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(2),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.warning,
                                                  size: 12,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${conv['user1_name'] ?? 'Unknown'} ↔ ${conv['user2_name'] ?? 'Unknown'}',
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              '${conv['message_count'] ?? 0} messages',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton(
                                        icon: const Icon(Icons.more_vert,
                                            size: 20),
                                        itemBuilder: (_) => [
                                          if (isReported)
                                            const PopupMenuItem(
                                              value: 'unreport',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.check,
                                                      color: Colors.green,
                                                      size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Dismiss Report'),
                                                ],
                                              ),
                                            ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete,
                                                    color: Colors.red,
                                                    size: 20),
                                                SizedBox(width: 8),
                                                Text('Delete'),
                                              ],
                                            ),
                                          ),
                                        ],
                                        onSelected: (value) {
                                          if (value == 'delete') {
                                            _deleteConversation(
                                                conv['id'].toString());
                                          } else if (value == 'unreport') {
                                            _unreportConversation(
                                                conv['id'].toString());
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  if (isReported) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.report,
                                                  size: 14,
                                                  color: Colors.red.shade700),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  'Reported by ${conv['reporter_name'] ?? 'Unknown'}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.red.shade700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (conv['report_reason'] != null &&
                                              conv['report_reason']
                                                  .toString()
                                                  .isNotEmpty)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Text(
                                                conv['report_reason'],
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade700,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = filterStatus == value;
    return Expanded(
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() {
          filterStatus = value;
          _filterConversations();
        }),
        selectedColor: Colors.purple.shade700,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade700,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildChatArea() {
    if (selectedConvId == null) {
      return Container(
        color: Colors.grey.shade50,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.admin_panel_settings,
                  size: 100, color: Colors.purple.shade200),
              const SizedBox(height: 16),
              Text(
                'Select a conversation',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a conversation from the list',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Only show header on desktop
        if (MediaQuery.of(context).size.width >= 600)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.purple,
                  child: Icon(Icons.people, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$selectedUser1 ↔ $selectedUser2',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            color: Colors.grey.shade50,
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('No messages yet',
                            style: GoogleFonts.poppins(
                                fontSize: 16, color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isAdmin =
                          msg['message'].toString().startsWith('[ADMIN]');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isAdmin
                              ? Colors.purple.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isAdmin
                                ? Colors.purple.shade200
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: isAdmin
                                  ? Colors.purple.shade700
                                  : Colors.blue.shade700,
                              child: Text(
                                msg['sender_name'][0].toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          msg['sender_name'],
                                          style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13),
                                        ),
                                      ),
                                      Text(
                                        _formatTime(
                                            msg['created_at']?.toString() ??
                                                ''),
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    msg['message'],
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isAdmin
                                          ? Colors.purple.shade900
                                          : Colors.black87,
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
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade700,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.admin_panel_settings,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: InputDecoration(
                      hintText: 'Send message as admin...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.purple.shade700,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays == 1) return 'Yesterday';
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }
}
