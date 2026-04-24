import '../models/market_channel_config.dart';
import '../models/market_type.dart';
import '../models/project_config.dart';

class LegacyProjectConfigImporter {
  const LegacyProjectConfigImporter._();

  static bool looksLikeLegacyProject(Map<String, dynamic> json) {
    return json.containsKey('appName') ||
        json.containsKey('apkDir') ||
        json.keys.any((key) => key.endsWith('Config'));
  }

  static ProjectConfig fromJson(Map<String, dynamic> json) {
    final appName = _readString(json['appName']);
    final packageName = _readString(json['packageName']);
    final apkDir = _readString(json['apkDir']);
    final updateConfig = _asMap(json['updateConfig']);
    final releaseNotes = _readString(updateConfig['updateDesc']);

    final channels = ProjectConfig.defaultChannels();
    _applyLegacyChannel(
      channels: channels,
      market: MarketType.huawei,
      legacyConfig: _asMap(json['huaweiConfig']),
      releaseNotes: releaseNotes,
    );
    _applyLegacyChannel(
      channels: channels,
      market: MarketType.xiaomi,
      legacyConfig: _asMap(json['xiaomiConfig']),
      releaseNotes: releaseNotes,
    );
    _applyLegacyChannel(
      channels: channels,
      market: MarketType.oppo,
      legacyConfig: _asMap(json['oppoConfig']),
      releaseNotes: releaseNotes,
    );
    _applyLegacyChannel(
      channels: channels,
      market: MarketType.vivo,
      legacyConfig: _asMap(json['vivoConfig']),
      releaseNotes: releaseNotes,
    );
    _applyLegacyChannel(
      channels: channels,
      market: MarketType.tencent,
      legacyConfig: _asMap(
        json['tencentConfig'],
        fallback: json['yingyongbaoConfig'],
      ),
      releaseNotes: releaseNotes,
    );

    final resolvedName = appName.isEmpty ? packageName : appName;
    final draft = ProjectConfig.create(
      name: resolvedName.isEmpty ? 'legacy-project' : resolvedName,
      packageName: packageName,
      basePackagePath: apkDir,
      outputDirectory: apkDir,
      channels: channels,
    );

    return draft.copyWith(
      id: packageName.isNotEmpty ? packageName : draft.id,
      name: resolvedName.isEmpty ? draft.name : resolvedName,
      packageName: packageName,
      basePackagePath: apkDir,
      outputDirectory: apkDir,
      channels: channels,
    );
  }

  static void _applyLegacyChannel({
    required Map<MarketType, MarketChannelConfig> channels,
    required MarketType market,
    required Map<String, dynamic> legacyConfig,
    required String releaseNotes,
  }) {
    if (legacyConfig.isEmpty) {
      return;
    }

    final fields = <String, String>{};
    final packageName = _readString(legacyConfig['packageName']);
    if (packageName.isNotEmpty) {
      fields['packageName'] = packageName;
    }

    switch (market) {
      case MarketType.huawei:
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'appId',
          sourceKeys: const ['appId'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'clientId',
          sourceKeys: const ['clientId'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'clientSecret',
          sourceKeys: const ['clientSecret'],
        );
        break;
      case MarketType.xiaomi:
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'userName',
          sourceKeys: const ['userName'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'publicPem',
          sourceKeys: const ['publicPem'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'privateKey',
          sourceKeys: const ['privateKey'],
        );
        break;
      case MarketType.oppo:
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'clientId',
          sourceKeys: const ['clientId', 'client_id'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'clientSecret',
          sourceKeys: const ['clientSecret', 'client_secret'],
        );
        break;
      case MarketType.vivo:
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'accessKey',
          sourceKeys: const ['accessKey', 'access_key'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'accessSecret',
          sourceKeys: const ['accessSecret', 'access_secret'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'appId',
          sourceKeys: const ['appId'],
        );
        break;
      case MarketType.tencent:
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'appId',
          sourceKeys: const ['appId'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'userId',
          sourceKeys: const ['userId'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'secretKey',
          sourceKeys: const ['secretKey'],
        );
        break;
      case MarketType.honor:
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'appId',
          sourceKeys: const ['appId'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'clientId',
          sourceKeys: const ['clientId'],
        );
        _copyField(
          fields,
          legacyConfig,
          targetKey: 'clientSecret',
          sourceKeys: const ['clientSecret'],
        );
        break;
    }

    channels[market] = MarketChannelConfig(
      market: market,
      enabled: legacyConfig['isEnable'] == true,
      endpoint: '',
      authToken: '',
      track: 'production',
      releaseNotes: releaseNotes,
      fields: fields,
    );
  }

  static void _copyField(
    Map<String, String> target,
    Map<String, dynamic> source, {
    required String targetKey,
    required List<String> sourceKeys,
  }) {
    for (final key in sourceKeys) {
      final value = _readString(source[key]);
      if (value.isNotEmpty) {
        target[targetKey] = value;
        return;
      }
    }
  }

  static Map<String, dynamic> _asMap(dynamic value, {dynamic fallback}) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (dynamic key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
      );
    }
    if (fallback != null) {
      return _asMap(fallback);
    }
    return const <String, dynamic>{};
  }

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }
}
