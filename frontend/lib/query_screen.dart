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
  final _queryController = TextEditingController();

  Map _response = {}; // to store backend response
  bool _isLoading = false;
  String lang = "de"; // default language
  String targetLang = "ko"; // default target language

  //Querys the backend for the given word and returns the response as a Map
  void queryBackend() async {
    //enable loading animation/logic
    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse(
      "http://127.0.0.1:8766/query",
    ); // backend address and port

    //query params
    final payload = {
      "word": _queryController.text,
      "lang": lang,
      "target_lang": targetLang,
      "tl_model": "NLLB",
      "debug": false,
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      setState(() {
        _response = {}; // reset response
        _response = jsonDecode(response.body); // returns Map<String, dynamic>
      });
      prettyPrint(_response);
    } else {
      throw Exception('Failed to query backend.. ㅠㅠ');
    }

    // clear input field
    _queryController.clear();

    //disable loading animation/logic
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Flexible(
              child: TextField(
                controller: _queryController,
                decoration: const InputDecoration(
                  labelText: "Enter word",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                prettyPrint(_response);
              },
              icon: Icon(Icons.text_snippet_outlined),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ElevatedButton(onPressed: queryBackend, child: const Text("Submit")),
        const SizedBox(height: 20),

        // Word header
        if (_response.containsKey("de") && !_isLoading)
          Text(
            _response["de"],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

        const SizedBox(height: 10),

        // Results
        _isLoading
            ? const CircularProgressIndicator()
            : _response.isEmpty
            ? const Text("Enter query above!")
            : Expanded(
                child: VocabCards(
                  entries: _response,
                  lang: lang,
                  targetLang: targetLang,
                ),
              ),
      ],
    );
  }
}

class VocabCards extends StatefulWidget {
  final Map<dynamic, dynamic> entries;
  final String lang;
  final String targetLang;

  final path = []; // path to the entry in the response map

  // Constructor
  VocabCards({
    super.key,
    required this.entries,
    required this.lang,
    required this.targetLang,
  });

  @override
  State<VocabCards> createState() => _VocabCardsState();
}

class _VocabCardsState extends State<VocabCards> {
  @override
  Widget build(BuildContext context) {
    var e = widget.entries;
    //create list of entries without the first entry ("de")
    final entryList = e.entries.toList();
    final query = entryList[0].value;
    entryList.removeAt(0); // remove "de" entry

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 20, 0),
            child: IconButton(
              onPressed: () {},
              icon: Icon(Icons.add),
              tooltip: "Adds a new entry",
              hoverColor: Colors.blue[100],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entryList.length,
            itemBuilder: (context, index) {
              final value = entryList[index].value;
              final key = entryList[index].key;

              return Card(
                child: ExpansionTile(
                  title: EditableTextCard(
                    content: "$query",
                    path: [...widget.path, key, "word"],
                    entries: widget.entries,
                    isBold: true,
                    fontSize: 18.0,
                  ),
                  subtitle: Text("${value["type"]}"),
                  children: value["senses"].entries
                      .map<Widget>(
                        (entry) => SenseCard(
                          sense: entry.value,
                          lang: widget.lang,
                          targetLang: widget.targetLang,
                          path: [...widget.path, key],
                          entries: widget.entries,
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SenseCard extends StatelessWidget {
  final Map<String, dynamic> sense;
  final String lang;
  final String targetLang;
  final List<String> path;
  final Map<dynamic, dynamic> entries;

  const SenseCard({
    super.key,
    required this.sense,
    required this.lang,
    required this.targetLang,
    required this.path,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
        child: ExpansionTile(
          backgroundColor: Colors.blue[244],
          collapsedBackgroundColor: Colors.white,
          title: EditableTextCard(
            content: sense[lang],
            path: [],
            entries: entries,
          ),
          subtitle: Text(sense['ko']),
          children: [],
        ),
      ),
    );
  }
}

class EditableTextCard extends StatefulWidget {
  //The actual string of the text card
  String content;
  //The path to the content in the response map
  List<String> path;
  final Map<dynamic, dynamic> entries;

  double fontSize = 16.0;
  bool isBold = false;
  double textWidth = 0.0;

  EditableTextCard({
    super.key,
    required this.content,
    required this.path,
    required this.entries,
    this.fontSize = 16.0,
    this.isBold = false,
  });

  @override
  State<EditableTextCard> createState() => _EditableTextCardState();
}

class _EditableTextCardState extends State<EditableTextCard> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content);
    _focusNode = FocusNode();

    // Listen for focus changes
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        // Focus lost → trigger logic
        setState(() {
          _isEditing = false; // go back to read-only
        });
      }
    });
    widget.textWidth = calculateTextWidth();
  }

  double calculateTextWidth() {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: widget.content,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: widget.isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return textPainter.size.width;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _isEditing
            ? Flexible(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(border: InputBorder.none),
                  onChanged: (value) {
                    setState(() {
                      widget.content = value;
                    });
                    // Update the entries map at the specified path
                    print(widget.path);
                    var current = widget.entries;
                    for (var i = 0; i < widget.path.length - 1; i++) {
                      current = current[widget.path[i]];
                    }
                    current[widget.path.last] = value;
                    widget.textWidth = calculateTextWidth();
                  },
                  autofocus: true,
                  onSubmitted: (value) {
                    setState(() {
                      _isEditing = false; // go back to read-only
                      widget.content = value;
                    });
                  },
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: widget.isBold
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              )
            : GestureDetector(
                onTap: () {
                  setState(() {
                    _isEditing = true; // switch to editing mode
                  });
                },
                child: Text(
                  widget.content,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: widget.isBold
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
        SizedBox(width: widget.textWidth),
      ],
    );
  }
}
