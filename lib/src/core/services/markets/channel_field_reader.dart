class ChannelFieldReader {
  ChannelFieldReader(Map<String, String> rawFields)
    : _normalized = <String, String>{
        for (final entry in rawFields.entries)
          _normalize(entry.key): entry.value,
      };

  final Map<String, String> _normalized;

  String requireAny(List<String> keys, {String? label}) {
    final value = optionalAny(keys);
    if (value == null || value.isEmpty) {
      throw StateError('Missing ${label ?? keys.join('/')}');
    }
    return value;
  }

  String? optionalAny(List<String> keys) {
    for (final key in keys) {
      final value = _normalized[_normalize(key)]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}
