import '../models/market_channel_config.dart';
import '../models/market_type.dart';

class MarketFieldDefinition {
  const MarketFieldDefinition({
    required this.key,
    required this.label,
    this.aliases = const <String>[],
    this.description = '',
    this.multiline = false,
    this.obscureText = false,
    this.width = 320,
  });

  final String key;
  final String label;
  final List<String> aliases;
  final String description;
  final bool multiline;
  final bool obscureText;
  final double width;

  List<String> get allKeys => <String>[key, ...aliases];
}

class MarketChannelSchema {
  const MarketChannelSchema({
    required this.market,
    required this.requiredFields,
    this.summary = '',
  });

  final MarketType market;
  final List<MarketFieldDefinition> requiredFields;
  final String summary;
}

class MarketChannelSchemas {
  const MarketChannelSchemas._();

  static MarketChannelSchema schemaOf(MarketType market) {
    return switch (market) {
      MarketType.huawei => const MarketChannelSchema(
        market: MarketType.huawei,
        summary: '启用前需要填写华为开放平台鉴权参数。',
        requiredFields: <MarketFieldDefinition>[
          MarketFieldDefinition(
            key: 'appId',
            label: 'App ID',
            aliases: <String>['app_id'],
          ),
          MarketFieldDefinition(
            key: 'clientId',
            label: 'Client ID',
            aliases: <String>['client_id'],
          ),
          MarketFieldDefinition(
            key: 'clientSecret',
            label: 'Client Secret',
            aliases: <String>['client_secret'],
            obscureText: true,
          ),
        ],
      ),
      MarketType.honor => const MarketChannelSchema(
        market: MarketType.honor,
        summary: '启用前需要填写华为开放平台鉴权参数。',
        requiredFields: <MarketFieldDefinition>[
          MarketFieldDefinition(
            key: 'appId',
            label: 'App ID',
            aliases: <String>['app_id'],
          ),
          MarketFieldDefinition(
            key: 'clientId',
            label: 'Client ID',
            aliases: <String>['client_id'],
          ),
          MarketFieldDefinition(
            key: 'clientSecret',
            label: 'Client Secret',
            aliases: <String>['client_secret'],
            obscureText: true,
          ),
        ],
      ),
      MarketType.xiaomi => const MarketChannelSchema(
        market: MarketType.xiaomi,
        summary: '启用前需要填写小米开发者账号与签名参数。',
        requiredFields: <MarketFieldDefinition>[
          MarketFieldDefinition(
            key: 'userName',
            label: '账号 / userName',
            aliases: <String>['user_name'],
          ),
          MarketFieldDefinition(
            key: 'publicPem',
            label: '公钥 PEM / publicPem',
            aliases: <String>['public_pem'],
            multiline: true,
            width: 420,
          ),
          MarketFieldDefinition(
            key: 'privateKey',
            label: '签名密码 / privateKey',
            aliases: <String>['private_key'],
            obscureText: true,
          ),
        ],
      ),
      MarketType.oppo => const MarketChannelSchema(
        market: MarketType.oppo,
        summary: '启用前需要填写 OPPO 开放平台鉴权参数。',
        requiredFields: <MarketFieldDefinition>[
          MarketFieldDefinition(
            key: 'clientId',
            label: 'Client ID',
            aliases: <String>['client_id'],
          ),
          MarketFieldDefinition(
            key: 'clientSecret',
            label: 'Client Secret',
            aliases: <String>['client_secret'],
            obscureText: true,
          ),
        ],
      ),
      MarketType.vivo => const MarketChannelSchema(
        market: MarketType.vivo,
        summary: '启用前需要填写 vivo 开发者平台鉴权参数。',
        requiredFields: <MarketFieldDefinition>[
          MarketFieldDefinition(
            key: 'accessKey',
            label: 'Access Key',
            aliases: <String>['access_key'],
          ),
          MarketFieldDefinition(
            key: 'accessSecret',
            label: 'Access Secret',
            aliases: <String>['access_secret'],
            obscureText: true,
          ),
          MarketFieldDefinition(
            key: 'appId',
            label: 'App ID',
            aliases: <String>['app_id'],
          ),
        ],
      ),
      MarketType.tencent => const MarketChannelSchema(
        market: MarketType.tencent,
        summary: '启用前需要填写应用宝开放平台鉴权参数。',
        requiredFields: <MarketFieldDefinition>[
          MarketFieldDefinition(
            key: 'appId',
            label: 'App ID',
            aliases: <String>['app_id'],
          ),
          MarketFieldDefinition(
            key: 'userId',
            label: 'User ID',
            aliases: <String>['user_id'],
          ),
          MarketFieldDefinition(
            key: 'secretKey',
            label: 'Secret Key',
            aliases: <String>['secret_key'],
            obscureText: true,
          ),
        ],
      ),
    };
  }

  static String? validateEnabledChannel(MarketChannelConfig channel) {
    if (!channel.enabled) {
      return null;
    }
    final missingLabels = missingFieldLabels(channel.market, channel.fields);
    if (missingLabels.isEmpty) {
      return null;
    }
    return '${channel.market.displayName} 缺少必填配置：${missingLabels.join('、')}';
  }

  static List<String> missingFieldLabels(
    MarketType market,
    Map<String, String> fields,
  ) {
    final schema = schemaOf(market);
    final missing = <String>[];
    for (final definition in schema.requiredFields) {
      final value = readField(fields, definition);
      if (value == null || value.isEmpty) {
        missing.add(definition.label);
      }
    }
    return missing;
  }

  static String? readField(
    Map<String, String> fields,
    MarketFieldDefinition definition,
  ) {
    final normalizedMap = <String, String>{};
    for (final entry in fields.entries) {
      normalizedMap[_normalizeKey(entry.key)] = entry.value;
    }
    for (final key in definition.allKeys) {
      final value = normalizedMap[_normalizeKey(key)]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static Map<String, String> stripKnownFields(
    MarketType market,
    Map<String, String> fields,
  ) {
    final knownKeys = schemaOf(
      market,
    ).requiredFields.expand((item) => item.allKeys).map(_normalizeKey).toSet();
    final result = <String, String>{};
    for (final entry in fields.entries) {
      if (!knownKeys.contains(_normalizeKey(entry.key))) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static String _normalizeKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}
