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

  Map<String, dynamic> _response = {}; // to store backend response
  String _query = "";
  bool _isLoading = false;
  String lang = "de"; // default language
  String targetLang = "ko"; // default target language
  final List<String> langSelection = ["en", "de", "ko"];

  //Querys the backend for the given word and returns the response as a Map
  void queryBackend() async {
    //enable loading animation/logic
    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse(
      "http://127.0.0.1:8766/query",
    ); // backend address and port

    _query = _queryController.text;

    //query params
    final payload = {
      "word": _query,
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Translating from "),
            DropdownButton<String>(
              value: lang,
              items: langSelection.map((lang) {
                return DropdownMenuItem(value: lang, child: Text(lang));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    lang = value;
                    _response = {};
                  });
                }
              },
            ),
            Text(" to "),
            DropdownButton<String>(
              value: targetLang,
              items: langSelection.map((lang) {
                return DropdownMenuItem(value: lang, child: Text(lang));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    targetLang = value;
                    _response = {};
                  });
                }
              },
            ),
          ],
        ),
        Row(
          children: [
            Flexible(
              child: TextField(
                controller: _queryController,
                onSubmitted: (value) => queryBackend(),
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
  int customEntryCount = 0;

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

    return Column(
      children: [
        Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                child: IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.add),
                  tooltip: "Adds a new entry",
                  hoverColor: Colors.blue[100],
                  style: ButtonStyle(elevation: WidgetStatePropertyAll(2.0)),
                ),
              ),
            ),
            // Word header
            if (widget.entries.containsKey(widget.lang))
              Align(
                alignment: Alignment.center,
                child: Text(
                  widget.entries[widget.lang],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        Divider(height: 3.0),
        Expanded(
          child: ListView.builder(
            itemCount: entryList.length,
            itemBuilder: (context, index) {
              final value = entryList[index].value;
              final key = entryList[index].key;

              return Card(
                child: ExpansionTile(
                  title: EditableTextCard(
                    content: value["word"],
                    path: [...widget.path, key, "word"],
                    entries: widget.entries,
                    isBold: true,
                    fontSize: 18.0,
                  ),
                  subtitle: EditableTextCard(
                    content: "${value["type"]}",
                    path: [...widget.path, key, "type"],
                    entries: widget.entries,
                  ),
                  children: value["senses"].entries
                      .map<Widget>(
                        (entry) => EntryCard(
                          sense: entry.value,
                          lang: widget.lang,
                          targetLang: widget.targetLang,
                          path: [...widget.path, key, "senses", entry.key],
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

class EntryCard extends StatelessWidget {
  final Map<String, dynamic> sense;
  final String lang;
  final String targetLang;
  final List<String> path;
  final Map<dynamic, dynamic> entries;

  const EntryCard({
    super.key,
    required this.sense,
    required this.lang,
    required this.targetLang,
    required this.path,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    List tl = sense["${targetLang}_tl"];
    List en_tl = sense["en_tl"];
    List tags = sense["tags"];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
        child: ExpansionTile(
          backgroundColor: Colors.blue[244],
          collapsedBackgroundColor: Colors.white,
          title: EditableTextCard(
            content: sense[lang],
            path: [...path, lang],
            entries: entries,
          ),
          subtitle: EditableTextCard(
            content: sense[targetLang],
            path: [...path, targetLang],
            entries: entries,
          ),
          children: [
            Column(
              children: [
                Row(
                  children: tags.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Chip(
                      label: EditableTextCard(
                        content: item.toString(),
                        path: [...path, "tags", index.toString()],
                        entries: entries,
                      ),
                    );
                  }).toList(),
                ),
                ExpansionTile(
                  title: Text(
                    "Translations:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: tl.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                      child: ListTile(
                        dense: true,
                        title: EditableTextCard(
                          content: item.toString(),
                          path: [...path, "${targetLang}_tl", index.toString()],
                          entries: entries,
                          fontSize: 14.0,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                ExpansionTile(
                  title: Text(
                    "English Translations:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: en_tl.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                      child: ListTile(
                        dense: true,
                        title: EditableTextCard(
                          content: item.toString(),
                          path: [...path, "en_tl", index.toString()],
                          entries: entries,
                          fontSize: 14.0,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
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
  }

  //will happen on gesture detector click
  void _moveCursor(TapDownDetails details) {
    final tapX = details.localPosition.dx;

    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.content,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: widget.isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Get character index at tap position
    final pos = textPainter.getPositionForOffset(Offset(tapX, 0));
    final offset = pos.offset - 1;

    setState(() {
      _controller.selection = TextSelection.collapsed(offset: offset);
    });
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
        //case: we are in edit mode -> show text field
        if (_isEditing)
          Flexible(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(border: InputBorder.none),
              onChanged: (value) {
                setState(() {
                  widget.content = value;
                });
                // Update the entries map at the specified path
                dynamic current = widget.entries;
                for (var i = 0; i < widget.path.length - 1; i++) {
                  var key = widget.path[i];

                  if (current is Map) {
                    current = current[key];
                  } else {
                    current = current[int.parse(key)];
                  }
                }
                // Now assign
                var lastKey = widget.path.last;
                if (current is Map) {
                  current[lastKey] = value;
                } else {
                  current[int.parse(lastKey)] = value;
                }
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
                fontWeight: widget.isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          )
        //case: we are not in edit mode and the string is not empty -> show text
        else if (widget.content != "")
          GestureDetector(
            onTapDown: (details) {
              _moveCursor(details);
              setState(() {
                _isEditing = true; // switch to editing mode
              });
            },
            child: Text(
              widget.content,
              style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: widget.isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          )
        //case: the string is empty -> show button to add
        else
          IconButton(
            onPressed: () {
              setState(() {
                _isEditing = true;
              });
            },
            icon: Icon(Icons.add),
          ),
        SizedBox(width: 20), //to give a little bit of a buffer to the right
      ],
    );
  }
}
