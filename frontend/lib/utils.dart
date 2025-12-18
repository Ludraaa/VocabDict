import 'dart:convert';

///Prettily prints a json object with indent
void prettyPrint(Map<dynamic, dynamic> jsonMap) {
  const encoder = JsonEncoder.withIndent('  '); // 2 spaces indentation
  final pretty = encoder.convert(jsonMap);
  print(pretty);
}

/// Walks through a JSON object using a given path and returns the value at the end of the path.
///
/// Parameters:
/// - `path`: A list of strings representing the path to the value in the JSON object.
/// - `json`: The JSON object to traverse.
///
/// Returns:
/// - The value at the end of the path in the JSON object.
dynamic walkJson(List<dynamic> path, Map<dynamic, dynamic> json) {
  //copy the json
  dynamic current = json;

  //if the path is empty, just return the whole json
  if (path.isEmpty) {
    return current;
  }

  //walk along the path
  for (var i = 0; i < path.length - 1; i++) {
    var key = path[i];

    if (current is Map) {
      current = current[key];
    } else if (current is List) {
      current = current[int.parse(key)];
    } else {
      throw Exception("Invalid path..");
    }
    //print(current.runtimeType);
    //prettyPrint(current);
  }

  //get the last value
  var lastKey = path.last;
  if (current is Map) {
    return current[lastKey];
  } else if (current is List) {
    return current[int.parse(lastKey)];
  } else {
    throw Exception("Invalid path at last key..");
  }
}
