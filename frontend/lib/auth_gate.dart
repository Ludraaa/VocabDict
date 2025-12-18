import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:frontend/query_screen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_screen.dart';
import 'entity_list_screen.dart';

final _storage = FlutterSecureStorage();

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? token;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final storage = FlutterSecureStorage();

    //Debug:
    final all = await storage.readAll();
    print("Stored key-values:");
    print(all);

    final t = await storage.read(key: "jwt");
    setState(() {
      print("Loaded token: $t");
      token = t;
      isLoading = false;
    });
  }

  //########################################################################################
  //These are passed down to the Entity Screen
  //Collection API functions
  Future<List<Entity>> fetchCollectionsFromApi() async {
    final token = await _storage.read(key: "jwt");

    if (token == null) {
      throw Exception("Not authenticated");
    }

    final response = await http.get(
      Uri.parse("http://127.0.0.1:8766/collections"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to load collections (${response.statusCode})");
    }

    final List<dynamic> decoded = jsonDecode(response.body);

    return decoded.map((e) => Entity.fromJson(e)).toList();
  }

  Future<void> createCollectionApi(String name) async {
    final token = await _storage.read(key: "jwt");

    if (token == null) {
      throw Exception("Not authenticated");
    }

    final response = await http.post(
      Uri.parse("http://127.0.0.1:8766/createCollection"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"name": name}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        "Failed to create collection (${response.statusCode}): ${response.body}",
      );
    }
  }

  Future<void> renameCollectionApi(int id, String newName) async {
    final token = await _storage.read(key: "jwt");

    if (token == null) throw Exception("Not authenticated");

    final response = await http.patch(
      Uri.parse("http://127.0.0.1:8766/collections/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"new_name": newName}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to rename collection (${response.statusCode}): ${response.body}",
      );
    }
  }

  Future<void> deleteCollectionApi(int id) async {
    final token = await _storage.read(key: "jwt");

    if (token == null) throw Exception("Not authenticated");

    final response = await http.delete(
      Uri.parse("http://127.0.0.1:8766/collections/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to delete collection (${response.statusCode}): ${response.body}",
      );
    }
  }
  //########################################################################################
  // Vocab API functions

  Future<List<Entity>> fetchVocabFromApi(int chapterId) async {
    final token = await _storage.read(key: "jwt");
    if (token == null) throw Exception("Not authenticated");

    final response = await http.get(
      Uri.parse("http://127.0.0.1:8766/chapters/$chapterId/vocab"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to load vocab (${response.statusCode})");
    }

    final List<dynamic> decoded = jsonDecode(response.body);
    return decoded.map((e) => Entity.fromJson(e)).toList();
  }

  Future<void> deleteVocabApi(int vocabId) async {
    final token = await _storage.read(key: "jwt");
    if (token == null) throw Exception("Not authenticated");

    final response = await http.delete(
      Uri.parse("http://127.0.0.1:8766/vocab/$vocabId"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to delete chapter (${response.statusCode}): ${response.body}",
      );
    }
  }

  Future<void> openVocabCreation(int chapterId, int? vocabId) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => QueryField(chapterId: chapterId, vocabId: vocabId),
      ),
    );
  }

  dynamic vocabScreenBuilder(Entity entity) {
    return EntityListScreen(
      title: "Content of ${entity.name}",
      fetchEntities: () => fetchVocabFromApi(entity.id),
      // Instead of creating immediately, navigate to the vocab creation screen
      createEntityApi: (_) => openVocabCreation(entity.id, null),
      deleteEntityApi: deleteVocabApi,
      onTapFunc: openVocabCreation,
      pageOnCreate: true,
      chapterId: entity.id,
      icon: Icon(Icons.text_fields, color: Colors.blue),
    );
  }

  //########################################################################################
  // Chapter API functions

  Future<List<Entity>> fetchChaptersFromApi(id) async {
    final token = await _storage.read(key: "jwt");

    if (token == null) {
      throw Exception("Not authenticated");
    }

    print("Fetching chapters for collection id: $id");

    final response = await http.get(
      Uri.parse("http://127.0.0.1:8766/collections/$id/chapters"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to load collections (${response.statusCode})");
    }

    final List<dynamic> decoded = jsonDecode(response.body);

    return decoded.map((e) => Entity.fromJson(e)).toList();
  }

  Future<void> createChapterApi(id, String name) async {
    final token = await _storage.read(key: "jwt");

    if (token == null) {
      throw Exception("Not authenticated");
    }

    final response = await http.post(
      Uri.parse("http://127.0.0.1:8766/collections/$id/chapters"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"name": name}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        "Failed to create collection (${response.statusCode}): ${response.body}",
      );
    }
  }

  Future<void> renameChapterApi(int chapterId, String newName) async {
    final token = await _storage.read(key: "jwt");
    if (token == null) throw Exception("Not authenticated");

    print("Renaming chapter $chapterId to $newName");

    final response = await http.patch(
      Uri.parse("http://127.0.0.1:8766/chapters/$chapterId"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"new_name": newName}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to rename chapter (${response.statusCode}): ${response.body}",
      );
    }
  }

  Future<void> deleteChapterApi(int chapterId) async {
    final token = await _storage.read(key: "jwt");
    if (token == null) throw Exception("Not authenticated");

    final response = await http.delete(
      Uri.parse("http://127.0.0.1:8766/chapters/$chapterId"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to delete chapter (${response.statusCode}): ${response.body}",
      );
    }
  }

  //#################################Chapter Screen Builder#################################
  dynamic chapterScreenBuilder(Entity entity) {
    return EntityListScreen(
      title: "Chapters of ${entity.name}",
      fetchEntities: () => fetchChaptersFromApi(entity.id),
      createEntityApi: (name) => createChapterApi(entity.id, name),
      renameEntityApi: renameChapterApi,
      deleteEntityApi: deleteChapterApi,
      nextScreenBuilder: vocabScreenBuilder,
      icon: Icon(Icons.bookmark_border, color: Colors.blue),
    );
  }

  //########################################################################################

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (token == null) {
      return LoginScreen(
        onLoginSuccess: (newToken) {
          setState(() => token = newToken);
          print(token);
        },
      );
    } else {
      return EntityListScreen(
        title: "Collections",
        fetchEntities: fetchCollectionsFromApi,
        createEntityApi: createCollectionApi,
        renameEntityApi: renameCollectionApi,
        deleteEntityApi: deleteCollectionApi,
        nextScreenBuilder: chapterScreenBuilder,
        icon: Icon(Icons.folder, color: Colors.blue),
      );
    }
  }
}
