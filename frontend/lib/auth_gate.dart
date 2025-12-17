import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_screen.dart';
import 'query_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? token;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final storage = FlutterSecureStorage();
    final t = await storage.read(key: "jwt");
    setState(() => token = t);
  }

  @override
  Widget build(BuildContext context) {
    if (token == null) {
      return LoginScreen(
        onLoginSuccess: (newToken) {
          setState(() => token = newToken);
          print(token);
        },
      );
    } else {
      return QueryField(
        //TODO: Logout function
        /*onLogout: () async {
          final storage = FlutterSecureStorage();
          await storage.delete(key: "jwt");
          setState(() => token = null);
        },*/
      );
    }
  }
}
