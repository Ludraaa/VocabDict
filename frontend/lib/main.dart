import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/auth_gate.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VocabDict',
      theme: ThemeData(
        brightness: Brightness.light, // optional, just for fallback
        primaryColor: Colors.blueGrey, // AppBar, buttons
      ),
      home: const MyHomePage(title: 'VocabDict Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    //these are just here to delete the stored tokens for testing
    //final storage = FlutterSecureStorage();
    //storage.deleteAll();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),

      body: Padding(padding: const EdgeInsets.all(16.0), child: AuthGate()),
    );
  }
}
