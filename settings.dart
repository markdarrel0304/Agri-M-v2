import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'login.dart';
import 'profile_management.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_provider.dart'; // Import ThemeProvider

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final storage = const FlutterSecureStorage();
  bool notificationsEnabled = true;
  bool emailNotifications = true;
  bool orderUpdates = true;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      emailNotifications = prefs.getBool('emailNotifications') ?? true;
      orderUpdates = prefs.getBool('orderUpdates') ?? true;
      loading = false;
    });
  }

  Future<void> _saveNotificationSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Logout', style: GoogleFonts.poppins()),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await storage.delete(key: 'jwt');
      await storage.delete(key: 'username');

      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the theme provider
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Settings', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green[700],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.poppins()),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Profile Section
          _buildSectionHeader('Profile'),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.person, color: Colors.blue),
                  ),
                  title: Text('My Profile',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  subtitle: const Text('View and edit your profile'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileManagementPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Appearance Section
          _buildSectionHeader('Appearance'),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: themeProvider.isDarkMode
                          ? Colors.grey.shade800
                          : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      themeProvider.isDarkMode
                          ? Icons.dark_mode
                          : Icons.light_mode,
                      color: themeProvider.isDarkMode
                          ? Colors.amber
                          : Colors.amber.shade700,
                    ),
                  ),
                  title: Text('Dark Mode',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    themeProvider.isDarkMode
                        ? 'Dark theme enabled'
                        : 'Light theme enabled',
                  ),
                  value: themeProvider.isDarkMode,
                  onChanged: (value) {
                    themeProvider.toggleTheme();
                  },
                  activeColor: Colors.green.shade700,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Notifications Section
          _buildSectionHeader('Notifications'),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.notifications,
                        color: Colors.orange.shade700),
                  ),
                  title: Text('Push Notifications',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  subtitle: const Text('Receive push notifications'),
                  value: notificationsEnabled,
                  onChanged: (value) {
                    setState(() => notificationsEnabled = value);
                    _saveNotificationSetting('notificationsEnabled', value);
                  },
                  activeColor: Colors.green.shade700,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.email, color: Colors.blue.shade700),
                  ),
                  title: Text('Email Notifications',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  subtitle: const Text('Receive notifications via email'),
                  value: emailNotifications,
                  onChanged: notificationsEnabled
                      ? (value) {
                          setState(() => emailNotifications = value);
                          _saveNotificationSetting('emailNotifications', value);
                        }
                      : null,
                  activeColor: Colors.green.shade700,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        Icon(Icons.shopping_bag, color: Colors.green.shade700),
                  ),
                  title: Text('Order Updates',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  subtitle: const Text('Get notified about order status'),
                  value: orderUpdates,
                  onChanged: notificationsEnabled
                      ? (value) {
                          setState(() => orderUpdates = value);
                          _saveNotificationSetting('orderUpdates', value);
                        }
                      : null,
                  activeColor: Colors.green.shade700,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // About Section
          _buildSectionHeader('About'),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.info, color: Colors.purple.shade700),
                  ),
                  title: Text('About App',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  subtitle: const Text('Version 1.0.0'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title:
                            Text('About Agri-M', style: GoogleFonts.poppins()),
                        content: const Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Agri-M Marketplace'),
                            SizedBox(height: 8),
                            Text('Version: 1.0.0'),
                            SizedBox(height: 8),
                            Text(
                                'A platform connecting farmers and buyers for agricultural products.'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.privacy_tip, color: Colors.teal.shade700),
                  ),
                  title: Text('Privacy Policy',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Privacy Policy - Coming soon'),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        Icon(Icons.description, color: Colors.indigo.shade700),
                  ),
                  title: Text('Terms of Service',
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Terms of Service - Coming soon'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Account Actions
          _buildSectionHeader('Account'),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.logout, color: Colors.red),
                  ),
                  title: Text('Logout',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.red)),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 16, color: Colors.red),
                  onTap: () => logout(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // App Info Footer
          Center(
            child: Text(
              'Agri-M © 2024',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
