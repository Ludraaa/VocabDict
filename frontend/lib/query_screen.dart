import 'package:flutter/material.dart';

import 'dart:convert'; // for jsonDecode
import 'package:http/http.dart' as http;
import 'utils.dart'; // for prettyPrint

///This class handles the input field and the button for querying the dictionary / backend,
///as well as language selection.
///This is then passed to VocabCards for rendering.
class QueryField extends StatefulWidget {
  const QueryField({super.key});

  @override
  State<QueryField> createState() => _QueryFieldState();
}

class _QueryFieldState extends State<QueryField> {
  //to listen to changes to the input field
  final _queryController = TextEditingController();

  //to listen to changes to the response that happen in children of this widget
  final ValueNotifier<Map<dynamic, dynamic>> _responseNotifier = ValueNotifier(
    {},
  );

  String _query = "";
  // for loading logic
  bool _isLoading = false;

  String lang = "de"; // default language
  String targetLang = "ko"; // default target language

  //Options for language selection, expand later..
  final List<String> langSelection = ["en", "de", "ko"];

  ///Performs a dictionary lookup + translation via the backend for the given word and returns the response as a Map
  void queryBackend() async {
    //enable loading animation/logic
    setState(() {
      _isLoading = true;
    });

    //get the text from the input field
    _query = _queryController.text;

    //backend address and port with parameters
    final url = Uri.parse(
      "http://127.0.0.1:8766/query?word=$_query&lang=$lang&target_lang=$targetLang&tl_model=NLLB",
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      setState(() {
        //reset response and set to results from backend
        _responseNotifier.value = {};
        _responseNotifier.value = jsonDecode(response.body);
      });
      //prettyPrint(_responseNotifier.value);
    } else {
      throw Exception(
        'Query lookup failed.. (${response.statusCode}): ${response.body}',
      );
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
        //Language selection
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Translating from "),
            //input language dropdown
            DropdownButton<String>(
              value: lang,
              items: langSelection.map((lang) {
                return DropdownMenuItem(value: lang, child: Text(lang));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    lang = value;
                    _responseNotifier.value = {};
                  });
                }
              },
            ),
            Text(" to "),
            //Target language dropdown
            DropdownButton<String>(
              value: targetLang,
              items: langSelection.map((lang) {
                return DropdownMenuItem(value: lang, child: Text(lang));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    targetLang = value;
                    _responseNotifier.value = {};
                  });
                }
              },
            ),
          ],
        ),
        //Textfield input (and temporary debug print button)
        Row(
          children: [
            Flexible(
              //input field
              child: TextField(
                controller: _queryController,
                onSubmitted: (value) => queryBackend(),
                decoration: const InputDecoration(
                  labelText: "Enter word",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            //debug print button
            IconButton(
              onPressed: () {
                prettyPrint(_responseNotifier.value);
              },
              icon: Icon(Icons.text_snippet_outlined),
            ),
          ],
        ),
        //Submit button with makeshift padding
        const SizedBox(height: 10),
        ElevatedButton(onPressed: queryBackend, child: const Text("Submit")),
        const SizedBox(height: 30),

        // Rendering of results /-/ loading animation
        _isLoading
            ? const CircularProgressIndicator()
            : _responseNotifier.value.isEmpty
            ? const Text("Enter query above!")
            : Expanded(
                child: VocabCards(
                  entriesNotifier: _responseNotifier,
                  lang: lang,
                  targetLang: targetLang,
                ),
              ),
      ],
    );
  }
}

///This class renders a list of vocabulary cards based on the response from the backend.
///
///It takes in the [ValueNotifier] of the Queryfield class that holds the response from the backend.
///It also takes in the [lang] and [targetLang] parameters for language selection.
///
///The class renders a vocabulary card in form of an [ExpansionTile] for every entry in the response map.
///Each card is contains word, type and senses if expanded.
///The senses of the word are rendered using [EntryCard] widgets.
///The class also maintains a [path] to the entry in the response map.
class VocabCards extends StatefulWidget {
  //backend response
  final ValueNotifier<Map<dynamic, dynamic>> entriesNotifier;

  final String lang;
  final String targetLang;

  final path = []; // path to the entry in the response map

  // Constructor
  VocabCards({
    super.key,
    required this.entriesNotifier,
    required this.lang,
    required this.targetLang,
  });

  @override
  State<VocabCards> createState() => _VocabCardsState();
}

class _VocabCardsState extends State<VocabCards> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(height: 3.0),
        //response content
        Expanded(
          //built from the response listener to support dynamic content
          child: ValueListenableBuilder(
            valueListenable: widget.entriesNotifier,
            builder: (context, entries, child) {
              //convert map to list for rendering
              final entryList = entries.entries.toList();

              return ListView.builder(
                itemCount: entryList.length,
                itemBuilder: (context, index) {
                  if (entryList[index].key != "add") {
                    // if the entry is not "add", add a card for it}
                    final value = entryList[index].value;
                    final key = entryList[index].key;

                    return Card(
                      child: ExpansionTile(
                        //word
                        title: EditableTextCard(
                          content: value["word"],
                          path: [...widget.path, key, "word"],
                          entriesNotifier: widget.entriesNotifier,
                          isBold: true,
                          fontSize: 18.0,
                        ),

                        //word type (noun, verb, etc.)
                        subtitle: EditableTextCard(
                          content: "${value["type"]}",
                          path: [...widget.path, key, "type"],
                          entriesNotifier: widget.entriesNotifier,
                        ),

                        //senses
                        children: value["senses"].entries
                            .map<Widget>(
                              (entry) => EntryCard(
                                sense: entry.value,
                                lang: widget.lang,
                                targetLang: widget.targetLang,
                                path: [
                                  ...widget.path,
                                  key,
                                  "senses",
                                  entry.key,
                                ],
                                entriesNotifier: widget.entriesNotifier,
                              ),
                            )
                            .toList(),
                      ),
                    );
                  } else {
                    //add the card to add a new entry
                    return AddCard(
                      lang: widget.lang,
                      targetLang: widget.targetLang,
                      entriesNotifier: widget.entriesNotifier,
                      path: widget.path,
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Displays a single sense of a word, including translations and tags.
/// Uses [EditableTextCard] widgets for editable fields and expands to show details.
class EntryCard extends StatelessWidget {
  //the sense to be displayed
  final Map<String, dynamic> sense;

  final String lang;
  final String targetLang;
  final List<String> path;
  final ValueNotifier<Map<dynamic, dynamic>> entriesNotifier;

  const EntryCard({
    super.key,
    required this.sense,
    required this.lang,
    required this.targetLang,
    required this.path,
    required this.entriesNotifier,
  });

  @override
  Widget build(BuildContext context) {
    List tl = sense["${targetLang}_tl"];
    List enTl = sense["en_tl"];
    List tags = sense["tags"];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
        child: ExpansionTile(
          backgroundColor: Colors.blue[244],
          collapsedBackgroundColor: Colors.white,
          //original language sense
          title: EditableTextCard(
            content: sense[lang],
            path: [...path, lang],
            entriesNotifier: entriesNotifier,
          ),
          //machine translated sense
          subtitle: EditableTextCard(
            content: sense[targetLang],
            path: [...path, targetLang],
            entriesNotifier: entriesNotifier,
          ),
          //translations, example sentences, etc.
          children: [
            Column(
              children: [
                //tags as chips, maybe change later
                //TODO: these currently break when trying to edit, fix this
                Row(
                  children: tags.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Chip(
                      label: EditableTextCard(
                        content: item.toString(),
                        path: [...path, "tags", index.toString()],
                        entriesNotifier: entriesNotifier,
                      ),
                    );
                  }).toList(),
                ),
                //Translations to target language
                ExpansionTile(
                  title: Text(
                    "Translations:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: tl.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                      child: ListTile(
                        dense: true,
                        title: EditableTextCard(
                          content: item.toString(),
                          path: [...path, "${targetLang}_tl", index.toString()],
                          entriesNotifier: entriesNotifier,
                          fontSize: 14.0,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                //Translations to english
                ExpansionTile(
                  title: Text(
                    "English Translations:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: enTl.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                      child: ListTile(
                        dense: true,
                        title: EditableTextCard(
                          content: item.toString(),
                          path: [...path, "en_tl", index.toString()],
                          entriesNotifier: entriesNotifier,
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

/// Displays a piece of text that can be edited in place upon clicking.
/// Updates the underlying response map at the specified [path] when changed.
class EditableTextCard extends StatefulWidget {
  //The actual string of the text card
  String content;

  //The path to the content in the response map
  List<String> path;
  final ValueNotifier<Map<dynamic, dynamic>> entriesNotifier;

  double fontSize = 16.0;
  bool isBold = false;

  EditableTextCard({
    super.key,
    required this.content,
    required this.path,
    required this.entriesNotifier,
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

    //get textpainter with the actual fontsize and style
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
    final offset = pos.offset;

    //set cursor position
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
                dynamic current = widget.entriesNotifier.value;
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
            //the text field has been clicked, trigger cursor offset logic and enable textfield
            onTapDown: (details) {
              _moveCursor(details);
              setState(() {
                _isEditing = true; // switch to editing mode
              });
            },
            //display the text as normal
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
            icon: Icon(Icons.edit_square),
          ),
        SizedBox(width: 20), //to give a little bit of a buffer to the right
      ],
    );
  }
}

class AddCard extends StatefulWidget {
  final List path;
  ValueNotifier<Map<dynamic, dynamic>> entriesNotifier;
  final String lang;
  final String targetLang;

  AddCard({
    super.key,
    required this.path,
    required this.entriesNotifier,
    required this.lang,
    required this.targetLang,
  });

  @override
  State<AddCard> createState() => _AddCardState();
}

class _AddCardState extends State<AddCard> {
  Future<void> add() async {
    //delete the temporary "add" key to make room for the new one (and organize ordering)
    widget.entriesNotifier.value.remove("add");

    final url = Uri.parse(
      "http://127.0.0.1:8766/get_empty_entry?lang=${widget.lang}&target_lang=${widget.targetLang}",
    ); // backend address and port

    final response = await http.get(url);

    if (response.statusCode == 200) {
      setState(() {
        final entry = jsonDecode(response.body);
        //iterate keys until we find a free one
        int i = 0;
        while (widget.entriesNotifier.value.containsKey("custom$i")) {
          i++;
        }
        widget.entriesNotifier.value = {
          ...widget.entriesNotifier.value,
          "custom$i": entry["custom"],
          "add": {},
        };
      });
      prettyPrint(widget.entriesNotifier.value);
    } else {
      throw Exception(
        "Backend request failed "
        "(${response.statusCode}): ${response.body}",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          onPressed: () {
            add();
          },
          icon: Icon(Icons.add),
          tooltip: "Adds a new entry",
        ),
      ),
    );
  }
}
