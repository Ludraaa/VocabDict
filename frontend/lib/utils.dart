import 'dart:convert';

String prettyPrint(Map<dynamic, dynamic> jsonMap) {
  const encoder = JsonEncoder.withIndent('  '); // 2 spaces indentation
  final pretty = encoder.convert(jsonMap);
  return pretty;
}
