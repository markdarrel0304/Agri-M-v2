import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TutorialPage extends StatefulWidget {
  final VoidCallback onComplete;

  const TutorialPage({super.key, required this.onComplete});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final PageController _pageController = PageController();
  final storage = const FlutterSecureStorage();
  int _currentPage = 0;

  final List<TutorialStep> _steps = [
    TutorialStep(
      title: 'Welcome to Agri-M! 🌾',
      description:
          'Your trusted marketplace for agricultural products with blockchain-powered transparency and security.',
      icon: Icons.agriculture,
      color: Colors.green,
    ),
    TutorialStep(
      title: 'Browse Products 🛒',
      description:
          'Discover fresh agricultural products directly from verified sellers. Tap on any product to view details and place orders.',
      icon: Icons.storefront,
      color: Colors.blue,
    ),
    TutorialStep(
      title: 'Secure Payments 💳',
      description:
          'Your payments are protected by escrow. Funds are only released to sellers after you confirm delivery.',
      icon: Icons.lock,
      color: Colors.orange,
    ),
    TutorialStep(
      title: 'Track Orders 📦',
      description:
          'Follow your order status in real-time from confirmation to delivery. Get notified at every step.',
      icon: Icons.local_shipping,
      color: Colors.purple,
    ),
    TutorialStep(
      title: 'Chat with Sellers 💬',
      description:
          'Communicate directly with sellers to ask questions, negotiate, or resolve issues. Share images of products.',
      icon: Icons.chat_bubble,
      color: Colors.teal,
    ),
    TutorialStep(
      title: 'Blockchain Verified ⛓️',
      description:
          'Every transaction is recorded on our blockchain for transparency. View supply chain history and product authenticity.',
      icon: Icons.link,
      color: Colors.indigo,
    ),
    TutorialStep(
      title: 'Become a Seller 🏪',
      description:
          'Want to sell? Request seller access from settings, get approved, and start listing your products!',
      icon: Icons.store,
      color: Colors.amber,
    ),
    TutorialStep(
      title: 'You\'re All Set! ✅',
      description:
          'Start exploring the marketplace now. Need help? Check settings for support options.',
      icon: Icons.check_circle,
      color: Colors.green,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeTutorial();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeTutorial() async {
    // Mark tutorial as completed
    await storage.write(key: 'tutorial_completed', value: 'true');
    widget.onComplete();
  }

  void _skipTutorial() async {
    await storage.write(key: 'tutorial_completed', value: 'true');
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _skipTutorial,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Page View
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return _buildTutorialStep(step, size, isDark);
                },
              ),
            ),

            // Page Indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _steps.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? _steps[_currentPage].color
                          : (isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),

            // Navigation Buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Previous Button
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousPage,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(
                            color: _steps[_currentPage].color,
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Back',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _steps[_currentPage].color,
                          ),
                        ),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 16),

                  // Next/Get Started Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _steps[_currentPage].color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _currentPage == _steps.length - 1
                            ? 'Get Started'
                            : 'Next',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorialStep(TutorialStep step, Size size, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with animated container
          TweenAnimationBuilder(
            duration: const Duration(milliseconds: 500),
            tween: Tween<double>(begin: 0, end: 1),
            builder: (context, double value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: step.color.withOpacity(0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: step.color.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    step.icon,
                    size: 80,
                    color: step.color,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 60),

          // Title
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),

          const SizedBox(height: 20),

          // Description
          Text(
            step.description,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 16,
              height: 1.6,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),

          const SizedBox(height: 40),

          // Feature highlights for specific steps
          if (step.icon == Icons.lock)
            _buildFeatureHighlight(
              'Escrow Protection',
              'Funds held safely until delivery',
              Icons.shield,
              step.color,
              isDark,
            ),
          if (step.icon == Icons.link)
            _buildFeatureHighlight(
              'Immutable Records',
              'Every transaction is permanent',
              Icons.verified,
              step.color,
              isDark,
            ),
          if (step.icon == Icons.chat_bubble)
            _buildFeatureHighlight(
              'Real-time Chat',
              'Instant communication with sellers',
              Icons.message,
              step.color,
              isDark,
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureHighlight(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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
}

class TutorialStep {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  TutorialStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

// Helper function to check if tutorial should be shown
Future<bool> shouldShowTutorial() async {
  const storage = FlutterSecureStorage();
  final completed = await storage.read(key: 'tutorial_completed');
  return completed != 'true';
}

// Helper function to check if tutorial icon should be shown (30 days from first login)
Future<bool> shouldShowTutorialIcon() async {
  const storage = FlutterSecureStorage();

  // Get first login date
  final firstLoginStr = await storage.read(key: 'first_login_date');

  // If no first login date, set it now
  if (firstLoginStr == null) {
    await storage.write(
        key: 'first_login_date', value: DateTime.now().toIso8601String());
    return true; // Show icon for new users
  }

  try {
    final firstLogin = DateTime.parse(firstLoginStr);
    final daysSinceFirstLogin = DateTime.now().difference(firstLogin).inDays;

    // Show icon for first 30 days
    return daysSinceFirstLogin <= 30;
  } catch (e) {
    return true; // If error parsing date, show icon
  }
}

// Helper function to reset tutorial (for testing or settings)
Future<void> resetTutorial() async {
  const storage = FlutterSecureStorage();
  await storage.delete(key: 'tutorial_completed');
}
