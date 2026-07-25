typedef JsonMap = Map<String, dynamic>;

Object? envelopeData(Object? value) {
  final map = jsonMapOrNull(value);
  if (map != null && map.containsKey('data')) {
    return map['data'];
  }
  return value;
}

JsonMap envelopeItem(Object? value, String key) {
  final data = envelopeData(value);
  final dataMap = jsonMapOrNull(data);
  if (dataMap == null) {
    return const {};
  }

  final keyed = jsonMapOrNull(dataMap[key]);
  if (keyed != null) {
    return keyed;
  }

  return dataMap;
}

List<JsonMap> envelopeList(Object? value, String key) {
  final data = envelopeData(value);
  if (data is List) {
    return data.map(jsonMap).where((item) => item.isNotEmpty).toList();
  }

  final dataMap = jsonMapOrNull(data);
  if (dataMap == null) {
    return const [];
  }

  final keyed = dataMap[key];
  if (keyed is List) {
    return keyed.map(jsonMap).where((item) => item.isNotEmpty).toList();
  }

  return const [];
}

JsonMap jsonMap(Object? value) => jsonMapOrNull(value) ?? const {};

JsonMap? jsonMapOrNull(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return null;
}

List<JsonMap> jsonMapList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map(jsonMap).where((item) => item.isNotEmpty).toList();
}

Object? field(JsonMap map, Iterable<String> keys) {
  for (final key in keys) {
    if (map.containsKey(key) && map[key] != null) {
      return map[key];
    }
  }
  return null;
}

String stringField(JsonMap map, Iterable<String> keys, {String fallback = ''}) {
  return field(map, keys)?.toString() ?? fallback;
}

String? nullableStringField(JsonMap map, Iterable<String> keys) {
  final value = field(map, keys);
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int intField(JsonMap map, Iterable<String> keys, {int fallback = 0}) {
  final value = field(map, keys);
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool boolField(JsonMap map, Iterable<String> keys, {bool fallback = false}) {
  final value = field(map, keys);
  if (value is bool) {
    return value;
  }
  final text = value?.toString().toLowerCase();
  if (text == 'true' || text == '1') {
    return true;
  }
  if (text == 'false' || text == '0') {
    return false;
  }
  return fallback;
}

DateTime dateTimeField(
  JsonMap map,
  Iterable<String> keys, {
  DateTime? fallback,
}) {
  return nullableDateTimeField(map, keys) ?? fallback ?? DateTime.now().toUtc();
}

DateTime? nullableDateTimeField(JsonMap map, Iterable<String> keys) {
  final value = field(map, keys);
  if (value is DateTime) {
    return value;
  }
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

Map<String, dynamic> compactMap(Map<String, dynamic> value) {
  return {
    for (final entry in value.entries)
      if (entry.value != null) entry.key: entry.value,
  };
}
