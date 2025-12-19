import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'analytics.dart';
import 'package:intl/intl.dart';

class ProfileManagementPage extends StatefulWidget {
  const ProfileManagementPage({super.key});

  @override
  State<ProfileManagementPage> createState() => _ProfileManagementPageState();
}

class _ProfileManagementPageState extends State<ProfileManagementPage> {
  final storage = const FlutterSecureStorage();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController bioController = TextEditingController();
  final TextEditingController currentPasswordController =
      TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController bankNameController = TextEditingController();
  final TextEditingController accountNumberController = TextEditingController();
  final TextEditingController accountNameController = TextEditingController();
  final TextEditingController otpController = TextEditingController();

  Map<String, dynamic> profile = {};
  Map<String, dynamic> sellerStats = {};
  List<dynamic> loginHistory = [];
  List<dynamic> activityLogs = [];
  List<dynamic> payoutAccounts = [];
  bool loading = true;
  bool isEditing = false;
  File? selectedImage;
  String? currentProfileImage;
  bool loadingStats = false;
  bool loadingLoginHistory = false;
  bool loadingActivityLogs = false;
  bool loadingPayoutAccounts = false;
  bool enabling2FA = false;
  bool verifying2FA = false;
  bool show2FASetup = false;
  bool get isTwoFactorEnabled =>
      profile['two_factor_enabled'] == 1 ||
      profile['two_factor_enabled'] == true;
  String? twoFactorQrCode;
  String? twoFactorSecret;

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
    fetchProfile();
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    addressController.dispose();
    bioController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    bankNameController.dispose();
    accountNumberController.dispose();
    accountNameController.dispose();
    otpController.dispose();
    super.dispose();
  }

  Future<void> fetchProfile() async {
    try {
      setState(() => loading = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/profile'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          profile = data['profile'];
          usernameController.text = profile['username'] ?? '';
          emailController.text = profile['email'] ?? '';
          phoneController.text = profile['phone'] ?? '';
          addressController.text = profile['address'] ?? '';
          bioController.text = profile['bio'] ?? '';
          currentProfileImage = profile['profile_image'];
          profile['two_factor_enabled'] = profile['two_factor_enabled'] == 1 ||
              profile['two_factor_enabled'] == true;
          loading = false;
        });

        // Fetch additional data
        fetchLoginHistory();
        fetchActivityLogs();

        if (profile['role'] == 'seller' && profile['is_approved'] == 1) {
          fetchSellerStats();
          fetchPayoutAccounts();
        }
      } else {
        setState(() => loading = false);
      }
    } catch (e) {
      setState(() => loading = false);
      _showSnackBar('Error loading profile: $e', Colors.red);
    }
  }

  Future<void> fetchSellerStats() async {
    try {
      setState(() => loadingStats = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/seller/profile-stats'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          sellerStats = data;
          loadingStats = false;
        });
      } else {
        setState(() => loadingStats = false);
      }
    } catch (e) {
      setState(() => loadingStats = false);
      print('Error fetching seller stats: $e');
    }
  }

  Future<void> fetchLoginHistory() async {
    try {
      setState(() => loadingLoginHistory = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/auth/login-history'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          loginHistory = data['login_history'] ?? [];
          loadingLoginHistory = false;
        });
      } else {
        setState(() => loadingLoginHistory = false);
      }
    } catch (e) {
      setState(() => loadingLoginHistory = false);
      print('Error fetching login history: $e');
    }
  }

  Future<void> fetchActivityLogs() async {
    try {
      setState(() => loadingActivityLogs = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/activity-logs'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          activityLogs = data['logs'] ?? [];
          loadingActivityLogs = false;
        });
      } else {
        setState(() => loadingActivityLogs = false);
      }
    } catch (e) {
      setState(() => loadingActivityLogs = false);
      print('Error fetching activity logs: $e');
    }
  }

  Future<void> fetchPayoutAccounts() async {
    try {
      setState(() => loadingPayoutAccounts = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$serverBaseUrl/api/seller/payout-accounts'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          payoutAccounts = data['accounts'] ?? [];
          loadingPayoutAccounts = false;
        });
      } else {
        setState(() => loadingPayoutAccounts = false);
      }
    } catch (e) {
      setState(() => loadingPayoutAccounts = false);
      print('Error fetching payout accounts: $e');
    }
  }

  Future<void> setupTwoFactorAuth() async {
    try {
      setState(() => enabling2FA = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/auth/setup-2fa'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          twoFactorQrCode = data['qr_code'];
          twoFactorSecret = data['secret'];
          show2FASetup = true;
          enabling2FA = false;
        });
      } else {
        setState(() => enabling2FA = false);
        _showSnackBar('Failed to setup 2FA', Colors.red);
      }
    } catch (e) {
      setState(() => enabling2FA = false);
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> verifyTwoFactorAuth() async {
    if (otpController.text.isEmpty) {
      _showSnackBar('Please enter OTP code', Colors.red);
      return;
    }

    try {
      setState(() => verifying2FA = true);
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/auth/verify-2fa'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'otp': otpController.text,
          'secret': twoFactorSecret,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        _showSnackBar('2FA enabled successfully!', Colors.green);
        setState(() {
          profile['two_factor_enabled'] = true;
          show2FASetup = false;
          twoFactorQrCode = null;
          twoFactorSecret = null;
          otpController.clear();
          verifying2FA = false;
        });
      } else {
        _showSnackBar(data['error'] ?? 'Invalid OTP code', Colors.red);
        setState(() => verifying2FA = false);
      }
    } catch (e) {
      setState(() => verifying2FA = false);
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> disableTwoFactorAuth() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/auth/disable-2fa'),
        headers: {"Authorization": "Bearer $token"},
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        _showSnackBar('2FA disabled successfully', Colors.green);
        setState(() {
          profile['two_factor_enabled'] = false;
        });
      } else {
        _showSnackBar(data['error'] ?? 'Failed to disable 2FA', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> addPayoutAccount() async {
    if (bankNameController.text.isEmpty ||
        accountNumberController.text.isEmpty ||
        accountNameController.text.isEmpty) {
      _showSnackBar('Please fill all fields', Colors.red);
      return;
    }

    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/seller/payout-accounts'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'bank_name': bankNameController.text,
          'account_number': accountNumberController.text,
          'account_name': accountNameController.text,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        _showSnackBar('Payout account added successfully!', Colors.green);
        bankNameController.clear();
        accountNumberController.clear();
        accountNameController.clear();
        Navigator.pop(context);
        await fetchPayoutAccounts();
      } else {
        _showSnackBar(data['error'] ?? 'Failed to add account', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> deletePayoutAccount(String accountId) async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      final response = await http.delete(
        Uri.parse('$serverBaseUrl/api/seller/payout-accounts/$accountId'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        _showSnackBar('Account deleted successfully', Colors.green);
        await fetchPayoutAccounts();
      } else {
        final data = json.decode(response.body);
        _showSnackBar(data['error'] ?? 'Failed to delete account', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> updateProfile() async {
    try {
      final token = await storage.read(key: 'jwt');
      if (token == null) return;

      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('$serverBaseUrl/api/profile'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['username'] = usernameController.text;
      request.fields['email'] = emailController.text;
      request.fields['phone'] = phoneController.text;
      request.fields['address'] = addressController.text;
      request.fields['bio'] = bioController.text;

      if (selectedImage != null) {
        var stream = http.ByteStream(selectedImage!.openRead());
        var length = await selectedImage!.length();
        var multipartFile = http.MultipartFile(
          'profile_image',
          stream,
          length,
          filename: selectedImage!.path.split('/').last,
        );
        request.files.add(multipartFile);
      }

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        _showSnackBar('Profile updated successfully!', Colors.green);
        setState(() {
          isEditing = false;
          selectedImage = null;
        });
        await fetchProfile();
        await storage.write(key: 'username', value: usernameController.text);
      } else {
        final data = json.decode(responseData);
        _showSnackBar(data['error'] ?? 'Failed to update profile', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> changePassword() async {
    if (newPasswordController.text != confirmPasswordController.text) {
      _showSnackBar('Passwords do not match', Colors.red);
      return;
    }

    if (newPasswordController.text.length < 6) {
      _showSnackBar('Password must be at least 6 characters', Colors.red);
      return;
    }

    try {
      final token = await storage.read(key: 'jwt');
      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/change-password'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: json.encode({
          'currentPassword': currentPasswordController.text,
          'newPassword': newPasswordController.text,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        _showSnackBar('Password changed successfully!', Colors.green);
        currentPasswordController.clear();
        newPasswordController.clear();
        confirmPasswordController.clear();
        Navigator.pop(context);
      } else {
        _showSnackBar(data['error'] ?? 'Failed to change password', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> pickImage() async {
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
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Change Password', style: GoogleFonts.poppins()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              currentPasswordController.clear();
              newPasswordController.clear();
              confirmPasswordController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: changePassword,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Change Password'),
          ),
        ],
      ),
    );
  }

  void _showTwoFactorDialog() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title:
                Text('Two-Factor Authentication', style: GoogleFonts.poppins()),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!show2FASetup && profile['two_factor_enabled'] != true)
                    if (profile['two_factor_enabled'] == true)
                      Column(
                        children: [
                          Icon(
                            Icons.security,
                            size: 64,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Add an extra layer of security to your account',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: enabling2FA ? null : setupTwoFactorAuth,
                            icon: const Icon(Icons.qr_code),
                            label: enabling2FA
                                ? const CircularProgressIndicator()
                                : const Text('Enable 2FA'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              minimumSize: const Size(double.infinity, 50),
                            ),
                          ),
                        ],
                      ),
                  if (show2FASetup && twoFactorQrCode != null)
                    Column(
                      children: [
                        Text(
                          'Scan QR code with Google Authenticator',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.network(
                            twoFactorQrCode!,
                            width: 200,
                            height: 200,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Or enter this secret key manually:',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            twoFactorSecret ?? '',
                            style: GoogleFonts.robotoMono(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: otpController,
                          decoration: const InputDecoration(
                            labelText: 'Enter 6-digit OTP',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_clock),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  if (profile['two_factor_enabled'] == true)
                    Column(
                      children: [
                        Icon(
                          Icons.verified_user,
                          size: 64,
                          color: Colors.green.shade700,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Two-Factor Authentication is enabled',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: disableTwoFactorAuth,
                          icon: const Icon(Icons.toggle_off),
                          label: const Text('Disable 2FA'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              if (show2FASetup)
                TextButton(
                  onPressed: () {
                    setState(() {
                      show2FASetup = false;
                      twoFactorQrCode = null;
                      twoFactorSecret = null;
                    });
                  },
                  child: const Text('Cancel'),
                ),
              if (show2FASetup && twoFactorQrCode != null)
                ElevatedButton(
                  onPressed: verifying2FA ? null : verifyTwoFactorAuth,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: verifying2FA
                      ? const CircularProgressIndicator()
                      : const Text('Verify & Enable'),
                ),
              if (!show2FASetup && !profile['two_factor_enabled'])
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Later'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showAddPayoutAccountDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add Payout Account', style: GoogleFonts.poppins()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bankNameController,
                decoration: const InputDecoration(
                  labelText: 'Bank Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.account_balance),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: accountNumberController,
                decoration: const InputDecoration(
                  labelText: 'Account Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: accountNameController,
                decoration: const InputDecoration(
                  labelText: 'Account Holder Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              bankNameController.clear();
              accountNumberController.clear();
              accountNameController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: addPayoutAccount,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Add Account'),
          ),
        ],
      ),
    );
  }

  void _showLoginHistoryDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.history, color: Colors.blue),
            const SizedBox(width: 10),
            Text('Login History', style: GoogleFonts.poppins()),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: loadingLoginHistory
              ? const Center(child: CircularProgressIndicator())
              : loginHistory.isEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_toggle_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No login history found',
                          style: GoogleFonts.poppins(),
                        ),
                      ],
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: loginHistory.length,
                      itemBuilder: (context, index) {
                        final login = loginHistory[index];
                        return ListTile(
                          leading: Icon(
                            login['success'] == true
                                ? Icons.check_circle
                                : Icons.error,
                            color: login['success'] == true
                                ? Colors.green
                                : Colors.red,
                          ),
                          title: Text(
                            login['ip_address'] ?? 'Unknown IP',
                            style: GoogleFonts.poppins(),
                          ),
                          subtitle: Text(
                            '${login['device'] ?? 'Unknown device'} • ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.parse(login['created_at']))}',
                          ),
                          trailing: Chip(
                            label: Text(
                              login['success'] == true ? 'Success' : 'Failed',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            backgroundColor: login['success'] == true
                                ? Colors.green
                                : Colors.red,
                          ),
                        );
                      },
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showActivityLogsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.assignment, color: Colors.orange),
            const SizedBox(width: 10),
            Text('Activity Logs', style: GoogleFonts.poppins()),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: loadingActivityLogs
              ? const Center(child: CircularProgressIndicator())
              : activityLogs.isEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.assignment_turned_in,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No activity logs found',
                          style: GoogleFonts.poppins(),
                        ),
                      ],
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: activityLogs.length,
                      itemBuilder: (context, index) {
                        final log = activityLogs[index];
                        return ListTile(
                          leading: _getActivityIcon(log['action_type']),
                          title: Text(
                            log['description'] ?? '',
                            style: GoogleFonts.poppins(),
                          ),
                          subtitle: Text(
                            DateFormat('MMM dd, yyyy HH:mm')
                                .format(DateTime.parse(log['created_at'])),
                          ),
                        );
                      },
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Icon _getActivityIcon(String actionType) {
    switch (actionType) {
      case 'login':
        return const Icon(Icons.login, color: Colors.blue);
      case 'logout':
        return const Icon(Icons.logout, color: Colors.blue);
      case 'profile_update':
        return const Icon(Icons.edit, color: Colors.green);
      case 'purchase':
        return const Icon(Icons.shopping_cart, color: Colors.purple);
      case 'review':
        return const Icon(Icons.star, color: Colors.orange);
      case 'password_change':
        return const Icon(Icons.lock, color: Colors.red);
      default:
        return const Icon(Icons.history, color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSeller = profile['role'] == 'seller' && profile['is_approved'] == 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('My Profile', style: GoogleFonts.poppins()),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (!isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => isEditing = true),
              tooltip: 'Edit Profile',
            ),
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  isEditing = false;
                  selectedImage = null;
                });
                fetchProfile();
              },
              tooltip: 'Cancel',
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchProfile,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Profile Picture
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 70,
                          backgroundColor: Colors.blue.shade100,
                          backgroundImage: selectedImage != null
                              ? FileImage(selectedImage!)
                              : (currentProfileImage != null
                                  ? NetworkImage(
                                      currentProfileImage!.startsWith('http')
                                          ? currentProfileImage!
                                          : '$serverBaseUrl$currentProfileImage',
                                    )
                                  : null) as ImageProvider?,
                          child: selectedImage == null &&
                                  currentProfileImage == null
                              ? Icon(
                                  Icons.person,
                                  size: 70,
                                  color: Colors.blue.shade700,
                                )
                              : null,
                        ),
                        if (isEditing)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              backgroundColor: Colors.blue.shade700,
                              radius: 20,
                              child: IconButton(
                                icon: const Icon(Icons.camera_alt,
                                    size: 20, color: Colors.white),
                                onPressed: pickImage,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // User Info Card
                    if (!isEditing)
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              _buildInfoRow(Icons.person, 'Username',
                                  profile['username']),
                              const Divider(),
                              _buildInfoRow(
                                  Icons.email, 'Email', profile['email']),
                              const Divider(),
                              _buildInfoRow(Icons.phone, 'Phone',
                                  profile['phone'] ?? 'Not set'),
                              const Divider(),
                              _buildInfoRow(Icons.location_on, 'Address',
                                  profile['address'] ?? 'Not set'),
                              const Divider(),
                              _buildInfoRow(Icons.info, 'Bio',
                                  profile['bio'] ?? 'Not set'),
                              const Divider(),
                              _buildInfoRow(Icons.badge, 'Role',
                                  (profile['role'] ?? 'buyer').toUpperCase()),
                              const Divider(),
                              _buildInfoRow(
                                Icons.security,
                                'Two-Factor Auth',
                                profile['two_factor_enabled'] == true
                                    ? 'Enabled ✓'
                                    : 'Disabled',
                              ),
                              const Divider(),
                              _buildInfoRow(
                                Icons.calendar_today,
                                'Member Since',
                                profile['created_at'] != null
                                    ? profile['created_at']
                                        .toString()
                                        .split('T')[0]
                                    : 'N/A',
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      // Edit Form
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              TextField(
                                controller: usernameController,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person),
                                ),
                              ),
                              const SizedBox(height: 15),
                              TextField(
                                controller: emailController,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.email),
                                ),
                              ),
                              const SizedBox(height: 15),
                              TextField(
                                controller: phoneController,
                                decoration: const InputDecoration(
                                  labelText: 'Phone',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.phone),
                                ),
                              ),
                              const SizedBox(height: 15),
                              TextField(
                                controller: addressController,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Address',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.location_on),
                                ),
                              ),
                              const SizedBox(height: 15),
                              TextField(
                                controller: bioController,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Bio',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.info),
                                ),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: updateProfile,
                                icon: const Icon(Icons.save),
                                label: const Text('Save Changes'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Seller Statistics Card
                    if (isSeller)
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Seller Statistics',
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const AnalyticsPage(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.analytics, size: 18),
                                    label: const Text('View Analytics'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 15),
                              if (loadingStats)
                                const Center(child: CircularProgressIndicator())
                              else
                                Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        _buildStatCard(
                                          'Products',
                                          sellerStats['total_products']
                                                  ?.toString() ??
                                              '0',
                                          Icons.inventory,
                                          Colors.blue,
                                        ),
                                        _buildStatCard(
                                          'Sales',
                                          sellerStats['total_sales']
                                                  ?.toString() ??
                                              '0',
                                          Icons.shopping_cart,
                                          Colors.green,
                                        ),
                                        _buildStatCard(
                                          'Rating',
                                          '${sellerStats['average_rating'] ?? '0.0'} ⭐',
                                          Icons.star,
                                          Colors.orange,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 15),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.green.shade200),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.monetization_on,
                                              color: Colors.green.shade700,
                                              size: 28),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Total Revenue',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              Text(
                                                '₱${(sellerStats['total_revenue'] ?? 0.0).toStringAsFixed(2)}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if ((sellerStats['total_ratings'] ?? 0) >
                                        0) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        '${sellerStats['total_ratings']} customer ratings',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Security & Activity Card
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading:
                                const Icon(Icons.history, color: Colors.blue),
                            title: Text('Login History',
                                style: GoogleFonts.poppins()),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: _showLoginHistoryDialog,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading:
                                const Icon(Icons.security, color: Colors.green),
                            title: Row(
                              children: [
                                Text('Two-Factor Authentication',
                                    style: GoogleFonts.poppins()),
                                const SizedBox(width: 8),
                                if (profile['two_factor_enabled'] == true)
                                  Icon(Icons.verified,
                                      size: 16, color: Colors.green),
                              ],
                            ),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: _showTwoFactorDialog,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.assignment,
                                color: Colors.orange),
                            title: Text('Activity Logs',
                                style: GoogleFonts.poppins()),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: _showActivityLogsDialog,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.lock, color: Colors.blue),
                            title: Text('Change Password',
                                style: GoogleFonts.poppins()),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: _showChangePasswordDialog,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Payout Accounts (For Sellers Only)
                    if (isSeller)
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Payout Accounts',
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _showAddPayoutAccountDialog,
                                    icon: const Icon(Icons.add_circle,
                                        color: Colors.blue),
                                    tooltip: 'Add Payout Account',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (loadingPayoutAccounts)
                                const Center(child: CircularProgressIndicator())
                              else if (payoutAccounts.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 20),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet,
                                        size: 64,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No payout accounts added',
                                        style: GoogleFonts.poppins(),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: _showAddPayoutAccountDialog,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Add Account'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: payoutAccounts.length,
                                  itemBuilder: (context, index) {
                                    final account = payoutAccounts[index];
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: ListTile(
                                        leading: Icon(
                                          Icons.account_balance,
                                          color: Colors.blue.shade700,
                                        ),
                                        title: Text(
                                          account['bank_name'] ?? '',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Account: ${account['account_number']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            Text(
                                              'Name: ${account['account_name']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title: const Text(
                                                    'Delete Account'),
                                                content: const Text(
                                                    'Are you sure you want to delete this payout account?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      deletePayoutAccount(
                                                          account['id']);
                                                    },
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Account Settings Card
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.privacy_tip,
                                color: Colors.green),
                            title: Text('Privacy Settings',
                                style: GoogleFonts.poppins()),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              _showSnackBar('Coming soon!', Colors.orange);
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.notifications,
                                color: Colors.orange),
                            title: Text('Notification Settings',
                                style: GoogleFonts.poppins()),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              _showSnackBar('Coming soon!', Colors.orange);
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade700, size: 24),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
