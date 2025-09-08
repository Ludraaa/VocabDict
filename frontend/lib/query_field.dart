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

  //Querys the backend for the given word and returns the response as a Map
  void queryBackend() async {
    final url = Uri.parse(
      "http://127.0.0.1:8766/query",
    ); // backend address and port

    //query params
    final payload = {
      "word": _queryController.text,
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
  }

  @override
  Widget build(BuildContext context) {
    // Grab entries (filter out "de")
    final entryList = _response.entries
        .where((e) => e.key != "de")
        .map((e) => MapEntry(e.key, e.value as Map<String, dynamic>))
        .toList();

    return Column(
      children: [
        TextField(
          controller: _queryController,
          decoration: const InputDecoration(
            labelText: "Enter word",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton(onPressed: queryBackend, child: const Text("Submit")),
        const SizedBox(height: 20),

        // Word header
        if (_response.containsKey("de"))
          Text(
            _response["de"],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

        const SizedBox(height: 10),

        // Results
        Expanded(
          child: entryList.isEmpty
              ? const Text("No results yet.")
              : ListView.builder(
                  itemCount: entryList.length,
                  itemBuilder: (context, entryIndex) {
                    final entry = entryList[entryIndex];
                    final entryId = entry.key;
                    final entryData = entry.value;
                    final senses =
                        (entryData["senses"] ?? {}) as Map<String, dynamic>;
                    final translations =
                        (entryData["tl"] ?? {}) as Map<String, dynamic>;

                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ExpansionTile(
                        title: Text(
                          "${entryData["type"] ?? "unknown"} (Entry $entryId)",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        children: senses.entries.map((senseEntry) {
                          final senseId = senseEntry.key;
                          final sense =
                              senseEntry.value as Map<String, dynamic>;

                          return Card(
                            margin: const EdgeInsets.all(8),
                            child: ExpansionTile(
                              title: Text(sense["de"] ?? ""),
                              subtitle: Text(sense["ko"] ?? ""),
                              children: [
                                // Tags
                                if (sense["tags"] != null &&
                                    (sense["tags"] as List).isNotEmpty)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: (sense["tags"] as List)
                                        .map(
                                          (tag) =>
                                              Chip(label: Text(tag.toString())),
                                        )
                                        .toList(),
                                  ),

                                // Korean translations
                                ExpansionTile(
                                  title: const Text(
                                    "Korean translations:",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  initiallyExpanded:
                                      true, // expanded by default
                                  children: (translations["ko"]?[senseId] ?? [""])
                                      .map<Widget>(
                                        (t) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12.0,
                                          ),
                                          child: TextFormField(
                                            initialValue: t.toString(),
                                            decoration: const InputDecoration(
                                              hintText:
                                                  "Enter Korean translation",
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),

                                // EN->KO translations
                                ExpansionTile(
                                  title: const Text(
                                    "EN → KO translations:",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  initiallyExpanded:
                                      true, // expanded by default
                                  children:
                                      (translations["en_to_ko"]?[senseId] ??
                                              [""])
                                          .map<Widget>(
                                            (t) => Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12.0,
                                                  ),
                                              child: TextFormField(
                                                initialValue: t.toString(),
                                                decoration: const InputDecoration(
                                                  hintText:
                                                      "Enter EN → KO translation",
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                ),

                                // English translations (still hidden by default)
                                if (translations["en"]?[senseId] != null)
                                  ExpansionTile(
                                    title: const Text(
                                      "English translations",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    initiallyExpanded:
                                        false, // hidden by default
                                    children:
                                        (translations["en"][senseId] as List)
                                            .map<Widget>(
                                              (t) => ListTile(
                                                title: Text(t.toString()),
                                              ),
                                            )
                                            .toList(),
                                  ),

                                // Examples section
                                if ((sense["de_ex"] != null &&
                                        sense["ko_ex"] != null) ||
                                    (sense["de_ex"] != null &&
                                        sense["ko_ex"] == null))
                                  ExpansionTile(
                                    title: const Text(
                                      "Examples",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    initiallyExpanded:
                                        true, // set false if you want them hidden by default
                                    children: List.generate(
                                      (sense["de_ex"] as List).length,
                                      (i) {
                                        final deEx =
                                            (sense["de_ex"] as List)[i];
                                        final koEx =
                                            (sense["ko_ex"] as List).length > i
                                            ? (sense["ko_ex"] as List)[i]
                                            : null;

                                        return ListTile(
                                          title: Text("• $deEx"),
                                          subtitle: koEx != null
                                              ? Text("→ $koEx")
                                              : null,
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
