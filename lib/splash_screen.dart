import 'package:flutter/material.dart';
import 'dart:async';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _controller.forward();

    Timer(const Duration(seconds: 3), () {
      _checkLoginState();
    });
  }

  Future<void> _checkLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      final userRole = prefs.getString('userRole');
      final userData = prefs.getString('userData');

      if (isLoggedIn && userRole != null && userData != null) {
        // User is already logged in, navigate to home
        final user = jsonDecode(userData);
        Get.offAllNamed('/home', arguments: {'role': userRole, 'user': user});
      } else {
        // User is not logged in, navigate to login page
        Get.offAllNamed('/login');
      }
    } catch (e) {
      // If there's any error, just go to login page
      Get.offAllNamed('/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3F2FD),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Image.asset(
                'assets/logo.png',
                height: 120,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Project Evaluation App',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004AAD),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'B G N U',
              style: TextStyle(
                fontSize: 16,
                letterSpacing: 2,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}