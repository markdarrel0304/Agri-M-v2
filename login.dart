import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dashboard.dart';
import 'register.dart';
import 'tutorial.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final storage = const FlutterSecureStorage();
  bool isLoading = false;
  bool rememberMe = false;
  bool obscurePassword = true;

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
    checkRememberMe();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> checkRememberMe() async {
    final savedEmail = await storage.read(key: 'saved_email');
    final savedPassword = await storage.read(key: 'saved_password');
    final rememberMeStatus = await storage.read(key: 'remember_me');

    if (rememberMeStatus == 'true' &&
        savedEmail != null &&
        savedPassword != null) {
      setState(() {
        emailController.text = savedEmail;
        passwordController.text = savedPassword;
        rememberMe = true;
      });
    }
  }

  Future<void> login() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      _showSnackBar('Please enter email and password', Colors.red);
      return;
    }

    setState(() => isLoading = true);

    final url = Uri.parse("$serverBaseUrl/api/login");

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': emailController.text.trim(),
          'password': passwordController.text,
        }),
      );

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['token'] != null) {
        final String token = data['token'] as String;
        final user = data['user'] ?? {};
        final String username = user['username'] ?? 'User';

        final bool isSeller =
            (user['role'] == 'seller' && user['is_approved'] == 1) ||
                (user['is_seller'] == 1);

        // Store credentials
        await storage.write(key: 'jwt', value: token);
        await storage.write(key: 'username', value: username);
        await storage.write(key: 'is_seller', value: isSeller.toString());
        await storage.write(
            key: 'role', value: user['role']?.toString() ?? 'buyer');
        await storage.write(
            key: 'is_approved', value: user['is_approved']?.toString() ?? '0');

        // Handle Remember Me
        if (rememberMe) {
          await storage.write(
              key: 'saved_email', value: emailController.text.trim());
          await storage.write(
              key: 'saved_password', value: passwordController.text);
          await storage.write(key: 'remember_me', value: 'true');
        } else {
          await storage.delete(key: 'saved_email');
          await storage.delete(key: 'saved_password');
          await storage.delete(key: 'remember_me');
        }

        if (!mounted) return;

        // ✅ CHECK IF TUTORIAL SHOULD BE SHOWN
        final showTutorial = await shouldShowTutorial();

        if (showTutorial) {
          // 🎓 Show tutorial first
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TutorialPage(
                onComplete: () {
                  // After tutorial, go to dashboard
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DashboardPage(
                        username: username,
                        isSeller: isSeller,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        } else {
          // ⏭️ Skip tutorial, go directly to dashboard
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                username: username,
                isSeller: isSeller,
              ),
            ),
          );
        }
      } else {
        if (!mounted) return;
        _showSnackBar(data['error'] ?? 'Login failed', Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error connecting to server: $e', Colors.red);
    }

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> forgotPassword() async {
    final emailResetController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.lock_reset, color: Colors.green[700]),
            const SizedBox(width: 10),
            Text('Reset Password', style: GoogleFonts.poppins()),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your email address and we\'ll send you a reset code.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: emailResetController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
              backgroundColor: Colors.green[700],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send Reset Code'),
          ),
        ],
      ),
    );

    if (result == true && emailResetController.text.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('$serverBaseUrl/api/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': emailResetController.text.trim()}),
        );

        final data = jsonDecode(response.body);

        if (response.statusCode == 200) {
          if (mounted) {
            _showResetCodeDialog(emailResetController.text.trim());
          }
        } else {
          _showSnackBar(
              data['error'] ?? 'Failed to send reset code', Colors.red);
        }
      } catch (e) {
        _showSnackBar('Error: $e', Colors.red);
      }
    }
  }

  Future<void> _showResetCodeDialog(String email) async {
    final codeController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Enter Reset Code', style: GoogleFonts.poppins()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'A reset code has been sent to $email',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Reset Code',
                  prefixIcon: const Icon(Icons.pin),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                _showSnackBar('Passwords do not match', Colors.red);
                return;
              }

              try {
                final response = await http.post(
                  Uri.parse('$serverBaseUrl/api/reset-password'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'email': email,
                    'code': codeController.text,
                    'newPassword': newPasswordController.text,
                  }),
                );

                final data = jsonDecode(response.body);

                if (response.statusCode == 200) {
                  Navigator.pop(context);
                  _showSnackBar(
                      'Password reset successful! Please login.', Colors.green);
                } else {
                  _showSnackBar(
                      data['error'] ?? 'Failed to reset password', Colors.red);
                }
              } catch (e) {
                _showSnackBar('Error: $e', Colors.red);
              }
            },
            child: const Text('Reset Password'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[50],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.agriculture,
                  size: 60,
                  color: Colors.green[800],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Agri-M',
                style: GoogleFonts.poppins(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
              Text(
                'Welcome Back!',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: Colors.green[600],
                ),
              ),
              const SizedBox(height: 40),

              // Email Field
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style:
                      const TextStyle(color: Colors.black87), // Add this line
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email, color: Colors.green[700]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Password Field
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  style:
                      const TextStyle(color: Colors.black87), // Add this line
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock, color: Colors.green[700]),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.green[700],
                      ),
                      onPressed: () {
                        setState(() => obscurePassword = !obscurePassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Remember Me & Forgot Password
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: rememberMe,
                        onChanged: (value) {
                          setState(() => rememberMe = value ?? false);
                        },
                        activeColor: Colors.green[700],
                      ),
                      Text(
                        'Remember me',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: forgotPassword,
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Login Button
              isLoading
                  ? CircularProgressIndicator(color: Colors.green[700])
                  : Container(
                      width: double.infinity,
                      height: 55,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.green[700]!,
                            Colors.green[500]!,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: login,
                        child: Text(
                          'Login',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 20),

              // Register Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen()),
                      );
                    },
                    child: Text(
                      'Register',
                      style: GoogleFonts.poppins(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
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
}
