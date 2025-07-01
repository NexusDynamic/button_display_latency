import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: ThemeMode.dark,
      home: const TestScreen(),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  bool _showFlash = false;

  void _onButtonPressed() {
    setState(() {
      _showFlash = true;
    });

    Future.delayed(const Duration(milliseconds: 20), () {
      if (mounted) {
        setState(() {
          _showFlash = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Listener(
              onPointerDown: (_) => _onButtonPressed(),
              child: Container(
                width: 150,
                height: 150,
                color: Colors.blue,
                alignment: Alignment.center,
                child: const Text(
                  'Press Me',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 50),
            Container(
              width: 200,
              height: 200,
              color: _showFlash ? Colors.white : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
