// Lenient readers for the API's JSON. A field with an unexpected type reads
// as missing, so a server change never crashes the host app.

String? readString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Map<String, dynamic> readMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
