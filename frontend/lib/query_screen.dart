import 'package:flutter/material.dart';

import 'dart:convert'; // for jsonDecode
import 'package:http/http.dart' as http;
import 'utils.dart'; // for prettyPrint
import 'package:web_socket_channel/web_socket_channel.dart'; // for WebSockets
import 'dart:math';

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

  //to store logging while querying
  String _log = "";

  //reference to the websocket (nullable)
  WebSocketChannel? _channel;

  String _query = "";

  // for loading logic
  bool _isLoading = false;

  String lang = "de"; // default language
  String targetLang = "ko"; // default target language

  //Options for language selection, expand later..
  final List<String> langSelection = ["en", "de", "ko"];

  ///Performs a dictionary lookup + translation via the backend for the given word and returns the response as a Map.
  void queryBackend() async {
    //enable loading animation/logic
    //reset log message and response
    setState(() {
      _isLoading = true;
      _log = "";
      _responseNotifier.value = {};
    });

    //get the text from the input field
    _query = _queryController.text;

    //backend address and port with parameters
    _channel = WebSocketChannel.connect(
      Uri.parse("ws://127.0.0.1:8766/ws/query"),
    );

    // Send query params as JSON
    _channel!.sink.add(
      jsonEncode({
        "word": _queryController.text,
        "lang": lang,
        "target_lang": targetLang,
        "tl_model": "NLLB",
      }),
    );

    //listen to the response stream
    _channel!.stream.listen((message) {
      //case: json
      try {
        final decoded = jsonDecode(message);

        if (decoded["type"] == "result") {
          setState(() {
            //get response json
            _responseNotifier.value = decoded["data"];

            //disable loading animation
            _isLoading = false;
          });
          _channel!.sink.close();
        }
        //case: not json -> log
      } catch (_) {
        //set message to log for display
        setState(() {
          _log = message;
        });
      }
    });

    // clear input field
    _queryController.clear();
  }

  ///Cancels the current query process by disconnecting the websocket.
  void cancelQuery() {
    //close connection if websocket is open (should always be the case..?)
    _channel?.sink.close();

    //disable loading animation
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: "Save",
        child: Icon(Icons.save),
      ),
      body: Column(
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
              ? Column(
                  children: [
                    CircularProgressIndicator(),
                    Text(_log),
                    ElevatedButton(
                      onPressed: cancelQuery,
                      child: Text("Cancel"),
                    ),
                  ],
                )
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
      ),
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
  final Map<String, ExpansibleController> controllers = {};
  final Map<String, bool> expandedStates = {};

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

                    // Create a unique controller and expanded flag for each key
                    controllers.putIfAbsent(key, () => ExpansibleController());
                    expandedStates.putIfAbsent(key, () => false);

                    final controller = controllers[key]!;
                    final isExpanded = expandedStates[key]!;

                    return Card(
                      child: ExpansionTile(
                        controller: controller,
                        trailing: SizedBox(
                          width: 90,
                          height: 100,
                          child: Row(
                            children: [
                              //delete button
                              IconButton(
                                icon: Icon(Icons.delete),
                                onPressed: () {
                                  setState(() {
                                    widget.entriesNotifier.value.remove(key);
                                  });
                                },
                              ),
                              IconButton(
                                icon: AnimatedRotation(
                                  turns: isExpanded ? 0.5 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Icon(Icons.expand_more),
                                ),
                                onPressed: () {
                                  setState(() {
                                    final newState = !isExpanded;
                                    expandedStates[key] = newState;

                                    var controller = controllers[key]!;

                                    if (newState) {
                                      controller.expand();
                                    } else {
                                      controller.collapse();
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        //make expansion tile state based on bool for expand button
                        onExpansionChanged: (expanded) {
                          setState(() => expandedStates[key] = expanded);
                        },
                        initiallyExpanded: isExpanded,

                        //removes the arrow
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
                        children: value["senses"].entries.map<Widget>((entry) {
                          //add sense logic if entry is "add"
                          if (entry.key == "add") {
                            return AddCard(
                              lang: widget.lang,
                              targetLang: widget.targetLang,
                              entriesNotifier: widget.entriesNotifier,
                              path: [...widget.path, key.toString(), "senses"],
                            );
                            //else case: entry is not "add", but an integer key
                          } else {
                            return EntryCard(
                              sense: entry.value,
                              lang: widget.lang,
                              targetLang: widget.targetLang,
                              path: [...widget.path, key, "senses", entry.key],
                              entriesNotifier: widget.entriesNotifier,
                            );
                          }
                        }).toList(),
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
class EntryCard extends StatefulWidget {
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
  State<EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<EntryCard> {
  bool isExpanded = false;

  final controller = ExpansibleController();

  @override
  Widget build(BuildContext context) {
    List tl = widget.sense["${widget.targetLang}_tl"];
    List enTl = widget.sense["en_tl"];
    List tags = widget.sense["tags"];

    Map<String, dynamic> examples = widget.sense["ex"];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
        child: ExpansionTile(
          controller: controller,
          trailing: SizedBox(
            width: 90,
            height: 100,
            child: Row(
              children: [
                //delete button
                IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () {
                    setState(() {
                      // clone the map (important for triggering ValueNotifier update)
                      final updatedValue = Map<String, dynamic>.from(
                        widget.entriesNotifier.value,
                      );

                      // walk to target part of the JSON
                      var resultAtPath = walkJson(
                        widget.path.sublist(0, widget.path.length - 1),
                        updatedValue,
                      );

                      // remove the targeted entry
                      resultAtPath.remove(widget.path.last);

                      // reassign to trigger listeners
                      widget.entriesNotifier.value = updatedValue;
                    });
                  },
                ),
                IconButton(
                  icon: AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more),
                  ),
                  onPressed: () {
                    setState(() {
                      isExpanded = !isExpanded;
                      if (isExpanded) {
                        controller.expand();
                      } else {
                        controller.collapse();
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          //make expansion tile state based on bool for expand button
          onExpansionChanged: (expanded) {
            setState(() => isExpanded = expanded);
          },
          initiallyExpanded: isExpanded,
          backgroundColor: Colors.blue[244],
          collapsedBackgroundColor: Colors.white,
          //original language sense
          title: EditableTextCard(
            content: widget.sense[widget.lang],
            path: [...widget.path, widget.lang],
            entriesNotifier: widget.entriesNotifier,
          ),
          //machine translated sense
          subtitle: EditableTextCard(
            content: widget.sense[widget.targetLang],
            path: [...widget.path, widget.targetLang],
            entriesNotifier: widget.entriesNotifier,
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
                        path: [...widget.path, "tags", index.toString()],
                        entriesNotifier: widget.entriesNotifier,
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
                    if (item != "add") {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                        child: ListTile(
                          dense: true,
                          title: EditableTextCard(
                            content: item.toString(),
                            path: [
                              ...widget.path,
                              "${widget.targetLang}_tl",
                              index.toString(),
                            ],
                            entriesNotifier: widget.entriesNotifier,
                            fontSize: 14.0,
                          ),
                        ),
                      );
                    } else {
                      return AddCard(
                        lang: widget.lang,
                        targetLang: widget.targetLang,
                        entriesNotifier: widget.entriesNotifier,
                        path: [...widget.path, "${widget.targetLang}_tl"],
                      );
                    }
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
                    if (item != "add") {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                        child: ListTile(
                          dense: true,
                          title: EditableTextCard(
                            content: item.toString(),
                            path: [...widget.path, "en_tl", index.toString()],
                            entriesNotifier: widget.entriesNotifier,
                            fontSize: 14.0,
                          ),
                        ),
                      );
                    } else {
                      return AddCard(
                        lang: widget.lang,
                        targetLang: "en",
                        entriesNotifier: widget.entriesNotifier,
                        path: [...widget.path, "en_tl"],
                      );
                    }
                  }).toList(),
                ),
                //Example sentences
                ExpansionTile(
                  title: Text(
                    "Example Sentences:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: examples.entries.map((entry) {
                    final key = entry.key;
                    final value = entry.value;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                      child: (key == "add")
                          ? AddCard(
                              lang: widget.lang,
                              targetLang: widget.targetLang,
                              path: [...widget.path, "ex"],
                              entriesNotifier: widget.entriesNotifier,
                            )
                          : ListTile(
                              dense: true,
                              title: EditableTextCard(
                                content: value["de"]?.toString() ?? "",
                                path: [...widget.path, "ex", key, "de"],
                                entriesNotifier: widget.entriesNotifier,
                                fontSize: 14.0,
                              ),
                              subtitle: EditableTextCard(
                                content: value["ko"]?.toString() ?? "",
                                path: [...widget.path, "ex", key, "ko"],
                                entriesNotifier: widget.entriesNotifier,
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
    final url = Uri.parse(
      "http://127.0.0.1:8766/get_empty_entry?lang=${widget.lang}&target_lang=${widget.targetLang}",
    ); // backend address and port

    final response = await http.get(url);

    if (response.statusCode == 200) {
      setState(() {
        var entry = jsonDecode(response.body);

        //get the part of the map at the specified path
        var resultsAtPath = walkJson(widget.path, widget.entriesNotifier.value);
        //prettyPrint(resultsAtPath);

        int i = -1;

        //do this now so walkJson still works with the general path and set the actual new index later
        entry = {"$i": entry["custom"]};

        //iterate keys until we find a free one, but only if the resultsAtPath is a map
        if (resultsAtPath.runtimeType != List) {
          while (resultsAtPath.containsKey("$i")) {
            i -= 1;
          }
        }
        print(widget.path);
        //get the empty entry starting at the specified path
        //if we add a new entry at the root, the path has to be []
        //otherwise, the path should be the widgets path except for the first one, which has to always be "-1"
        dynamic emptyAtPath;
        //we dont need to walk the path if we add a new entry at the root
        if (widget.path.isEmpty) {
          emptyAtPath = entry;
        } else {
          emptyAtPath = walkJson([
            "-1",
            ...widget.path.sublist(min(1, widget.path.length)),
          ], entry);
        }

        //get the wanted key (there should only ever be a single key, apart from the "add" key)
        //we can skip this if we touch a list instead of a map
        if (emptyAtPath.runtimeType != List) {
          var key = emptyAtPath.keys.first;
          emptyAtPath = {"$i": emptyAtPath[key]};
        }

        //delete and add "add" again, as it should be the last key
        if (resultsAtPath.runtimeType != List) {
          //append empty entry to the map at the specified path
          resultsAtPath.addAll(emptyAtPath);

          resultsAtPath.remove("add");
          resultsAtPath["add"] = {};
        } else {
          //append empty string to the list at the specified path
          resultsAtPath.add("");

          resultsAtPath.remove("add");
          resultsAtPath.add("add");
        }

        //set value listener to trigger a rebuild
        var curr = widget.entriesNotifier.value;
        widget.entriesNotifier.value = Map<dynamic, dynamic>.from(curr);
      });
      //prettyPrint(widget.entriesNotifier.value);
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
