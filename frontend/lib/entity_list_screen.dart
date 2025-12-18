import 'package:flutter/material.dart';

class Entity {
  final int id;
  String name;

  Entity({required this.id, required this.name});

  factory Entity.fromJson(Map<String, dynamic> json) {
    return Entity(id: json['id'] as int, name: json['name'] as String);
  }
}

class EntityListScreen extends StatefulWidget {
  final String title;
  final Future<List<Entity>> Function() fetchEntities;
  final Future<void> Function(String name) createEntityApi;
  final Future<void> Function(int id, String newName)? renameEntityApi;
  final Future<void> Function(int id) deleteEntityApi;
  final Future<dynamic> Function(int, int)? onTapFunc;
  final Icon icon;

  //Whether the create button opens a seperate page or a dialog
  final bool pageOnCreate;
  final int? chapterId;

  /// Optional builder to create a screen when an entity is tapped
  final dynamic Function(Entity entity)? nextScreenBuilder;

  const EntityListScreen({
    super.key,
    required this.title,
    required this.fetchEntities,
    required this.createEntityApi,
    required this.deleteEntityApi,
    this.onTapFunc,
    this.renameEntityApi,
    this.icon = const Icon(Icons.folder, color: Colors.blue),
    this.nextScreenBuilder,
    this.pageOnCreate = false,
    this.chapterId,
  });

  @override
  State<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends State<EntityListScreen> {
  bool loading = true;
  List<Entity> entities = [];

  @override
  void initState() {
    super.initState();
    _loadEntities();
  }

  Future<void> _loadEntities() async {
    setState(() => loading = true);
    entities = await widget.fetchEntities();
    setState(() => loading = false);
  }

  void _showCreateDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          "Create ${widget.title.substring(0, widget.title.length - 1)}",
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Create"),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await widget.createEntityApi(name);
      _loadEntities();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (!widget.pageOnCreate) {
            _showCreateDialog();
          } else {
            await widget.createEntityApi("");
            _loadEntities();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: entities.length,
              itemBuilder: (context, index) {
                final entity = entities[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: widget.icon,
                    title: Text(entity.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.renameEntityApi != null)
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: "Rename",
                            onPressed: () async {
                              final controller = TextEditingController(
                                text: entity.name,
                              );
                              final newName = await showDialog<String>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("Rename"),
                                  content: TextField(
                                    controller: controller,
                                    autofocus: true,
                                    onSubmitted: (v) =>
                                        Navigator.pop(context, v.trim()),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Cancel"),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(
                                        context,
                                        controller.text.trim(),
                                      ),
                                      child: const Text("Rename"),
                                    ),
                                  ],
                                ),
                              );

                              if (newName != null && newName.isNotEmpty) {
                                await widget.renameEntityApi!(
                                  entity.id,
                                  newName,
                                );
                                setState(() => entity.name = newName);
                              }
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: "Delete",
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text("Confirm Delete"),
                                content: Text(
                                  "Are you sure you want to delete ${entity.name}?",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text("Cancel"),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text("Delete"),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed == true) {
                              await widget.deleteEntityApi(entity.id);
                              setState(() => entities.removeAt(index));
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () async {
                      if (widget.nextScreenBuilder != null &&
                          widget.onTapFunc == null) {
                        final result = await widget.nextScreenBuilder!(entity);

                        if (result is Widget) {
                          // Wrap in a page and push
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => result),
                          );
                        } else {
                          // Optionally handle unexpected type
                          throw Exception(
                            "nextScreenBuilder returned unexpected type: $result",
                          );
                        }
                      } else if (widget.onTapFunc != null) {
                        // Open vocab creation/editing screen
                        await widget.onTapFunc!(widget.chapterId!, entity.id);
                        _loadEntities();
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
