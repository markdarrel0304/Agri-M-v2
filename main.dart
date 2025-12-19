import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'login.dart';
import 'dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final storage = const FlutterSecureStorage();
  bool _isLoading = true;
  Widget? _initialScreen;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final token = await storage.read(key: 'jwt');
    final username = await storage.read(key: 'username');

    setState(() {
      if (token != null && username != null) {
        _initialScreen = DashboardPage(username: username);
      } else {
        _initialScreen = const LoginScreen();
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        print(
            '🔄 Building app: isDarkMode = ${themeProvider.isDarkMode}, isInitialized = ${themeProvider.isInitialized}');

        if (!themeProvider.isInitialized) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
            ),
            home: const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        return MaterialApp(
          title: 'Agri-M',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.green,
              brightness: Brightness.light,
            ),
            appBarTheme: AppBarTheme(
              elevation: 0,
              centerTitle: false,
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              systemOverlayStyle: SystemUiOverlayStyle.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.green,
              brightness: Brightness.dark,
            ),
            appBarTheme: AppBarTheme(
              elevation: 0,
              centerTitle: false,
              backgroundColor: Colors.green.shade900,
              foregroundColor: Colors.white,
              systemOverlayStyle: SystemUiOverlayStyle.light,
            ),
          ),
          themeMode:
              themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: _isLoading
              ? const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              : _initialScreen ?? const LoginScreen(),
          builder: (context, child) {
            // Prevent text scaling beyond reasonable limits
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaleFactor:
                    MediaQuery.of(context).textScaleFactor.clamp(0.8, 1.2),
              ),
              child: child!,
            );
          },
        );
      },
    );
  }
}
