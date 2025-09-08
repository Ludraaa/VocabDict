import 'dart:convert';

void prettyPrint(Map<dynamic, dynamic> jsonMap) {
  const encoder = JsonEncoder.withIndent('  '); // 2 spaces indentation
  final pretty = encoder.convert(jsonMap);
  print(pretty);
}
