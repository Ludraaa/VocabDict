import 'dart:convert';

//Prettily prints a json object with indent
void prettyPrint(Map<dynamic, dynamic> jsonMap) {
  const encoder = JsonEncoder.withIndent('  '); // 2 spaces indentation
  final pretty = encoder.convert(jsonMap);
  print(pretty);
}

//Creates an empty json, like the ones returned by the backend query
Map<String, dynamic> createResultObject(lang, targetLang, index) {
  return {
    //lang: "",
    //index: {
    //  "type": "",
    //   "word": "",
    //  "senses":
    //}
    //};//try to nest this all so it takes no duplicate code
  };
}
