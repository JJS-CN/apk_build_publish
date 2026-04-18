import 'market_type.dart';

class MarketChannelConfig {
  const MarketChannelConfig({
    required this.market,
    this.enabled = false,
    this.endpoint = '',
    this.authToken = '',
    this.track = 'production',
    this.releaseNotes = '',
    this.headers = const <String, String>{},
    this.fields = const <String, String>{},
  });

  final MarketType market;
  final bool enabled;
  final String endpoint;
  final String authToken;
  final String track;
  final String releaseNotes;
  final Map<String, String> headers;
  final Map<String, String> fields;

  MarketChannelConfig copyWith({
    MarketType? market,
    bool? enabled,
    String? endpoint,
    String? authToken,
    String? track,
    String? releaseNotes,
    Map<String, String>? headers,
    Map<String, String>? fields,
  }) {
    return MarketChannelConfig(
      market: market ?? this.market,
      enabled: enabled ?? this.enabled,
      endpoint: endpoint ?? this.endpoint,
      authToken: authToken ?? this.authToken,
      track: track ?? this.track,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      headers: headers ?? this.headers,
      fields: fields ?? this.fields,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'market': market.id,
      'enabled': enabled,
      'endpoint': endpoint,
      'authToken': authToken,
      'track': track,
      'releaseNotes': releaseNotes,
      'headers': headers,
      'fields': fields,
    };
  }

  factory MarketChannelConfig.fromJson(Map<String, dynamic> json) {
    return MarketChannelConfig(
      market:
          MarketType.tryParse(json['market'] as String? ?? '') ??
          MarketType.huawei,
      enabled: json['enabled'] as bool? ?? false,
      endpoint: json['endpoint'] as String? ?? '',
      authToken: json['authToken'] as String? ?? '',
      track: json['track'] as String? ?? 'production',
      releaseNotes: json['releaseNotes'] as String? ?? '',
      headers: _stringMapFrom(json['headers']),
      fields: _stringMapFrom(json['fields']),
    );
  }

  static Map<String, String> _stringMapFrom(dynamic value) {
    if (value is! Map) {
      return const <String, String>{};
    }
    return value.map(
      (dynamic key, dynamic mapValue) =>
          MapEntry(key.toString(), mapValue?.toString() ?? ''),
    );
  }
}
