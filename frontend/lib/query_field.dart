import 'package:flutter/material.dart';

import 'dart:convert'; // for jsonDecode
import 'package:http/http.dart' as http;
import 'utils.dart'; // for prettyPrint

class QueryField extends StatefulWidget {
  const QueryField({super.key});

  @override
  State<QueryField> createState() => _QueryFieldState();
}

class _QueryFieldState extends State<QueryField> {
  final _controller = TextEditingController();

  Map _response = {}; // to store backend response

  //Querys the backend for the given word and returns the response as a Map
  void queryBackend() async {
    final url = Uri.parse(
      "http://127.0.0.1:8766/query",
    ); // backend address and port

    //query params
    final payload = {
      "word": _controller.text,
      "lang": "de",
      "target_lang": "ko",
      "tl_model": "NLLB",
      "debug": false,
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      _response = jsonDecode(response.body); // returns Map<String, dynamic>
      prettyPrint(_response);
    } else {
      throw Exception('Failed to query backend.. ㅠㅠ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: "Enter word",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            queryBackend();
            setState(() {}); // refresh UI
          },
          child: const Text("Submit"),
        ),
        Text(jsonEncode(_response), style: const TextStyle(fontSize: 16)),
      ],
    );
  }
}
