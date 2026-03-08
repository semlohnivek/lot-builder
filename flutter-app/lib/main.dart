import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const LotBuilderApp());
}

class LotBuilderApp extends StatelessWidget {
  const LotBuilderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lot Builder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
