import 'package:flutter/material.dart';
import 'login_page.dart';

void main() {
  runApp(TransportApp());
}

class TransportApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "College Transport System",
      home: LoginPage(),
    );
  }
}