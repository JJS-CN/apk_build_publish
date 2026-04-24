import 'market_channel_config.dart';
import 'market_type.dart';
import 'signing_config.dart';

class ProjectConfig {
  const ProjectConfig({
    required this.id,
    required this.name,
    required this.packageName,
    required this.basePackagePath,
    required this.outputDirectory,
    required this.signing,
    required this.channels,
  });

  final String id;
  final String name;
  final String packageName;
  final String basePackagePath;
  final String outputDirectory;
  final SigningConfig signing;
  final Map<MarketType, MarketChannelConfig> channels;

  factory ProjectConfig.create({
    required String name,
    String packageName = '',
    String basePackagePath = '',
    String outputDirectory = '',
    SigningConfig signing = const SigningConfig(),
    Map<MarketType, MarketChannelConfig>? channels,
  }) {
    final normalizedName = name.trim();
    return ProjectConfig(
      id: _slugify(normalizedName),
      name: normalizedName,
      packageName: packageName,
      basePackagePath: basePackagePath,
      outputDirectory: outputDirectory,
      signing: signing,
      channels: channels ?? defaultChannels(),
    );
  }

  factory ProjectConfig.empty() {
    return ProjectConfig.create(name: 'new-project');
  }

  ProjectConfig copyWith({
    String? id,
    String? name,
    String? packageName,
    String? basePackagePath,
    String? outputDirectory,
    SigningConfig? signing,
    Map<MarketType, MarketChannelConfig>? channels,
  }) {
    return ProjectConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      packageName: packageName ?? this.packageName,
      basePackagePath: basePackagePath ?? this.basePackagePath,
      outputDirectory: outputDirectory ?? this.outputDirectory,
      signing: signing ?? this.signing,
      channels: channels ?? this.channels,
    );
  }

  List<MarketChannelConfig> get orderedChannels {
    return MarketType.values
        .map(
          (market) => channels[market] ?? MarketChannelConfig(market: market),
        )
        .toList();
  }

  List<MarketType> get enabledMarkets {
    return orderedChannels
        .where((channel) => channel.enabled)
        .map((channel) => channel.market)
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'packageName': packageName,
      'basePackagePath': basePackagePath,
      'outputDirectory': outputDirectory,
      'signing': signing.toJson(),
      'channels': {
        for (final entry in channels.entries)
          entry.key.id: entry.value.toJson(),
      },
    };
  }

  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'];
    final channels = <MarketType, MarketChannelConfig>{};
    if (rawChannels is Map) {
      for (final entry in rawChannels.entries) {
        final market = MarketType.tryParse(entry.key.toString());
        final value = entry.value;
        if (market != null && value is Map<String, dynamic>) {
          channels[market] = MarketChannelConfig.fromJson(value);
        } else if (market != null && value is Map) {
          channels[market] = MarketChannelConfig.fromJson(
            value.map(
              (dynamic key, dynamic mapValue) =>
                  MapEntry(key.toString(), mapValue),
            ),
          );
        }
      }
    }

    return ProjectConfig(
      id:
          json['id'] as String? ??
          _slugify(json['name'] as String? ?? 'project'),
      name: json['name'] as String? ?? 'Unnamed Project',
      packageName: json['packageName'] as String? ?? '',
      basePackagePath: json['basePackagePath'] as String? ?? '',
      outputDirectory: json['outputDirectory'] as String? ?? '',
      signing: SigningConfig.fromJson(json['signing'] as Map<String, dynamic>?),
      channels: mergeWithDefaults(channels),
    );
  }

  static Map<MarketType, MarketChannelConfig> defaultChannels() {
    return {
      for (final market in MarketType.values)
        market: MarketChannelConfig(market: market),
    };
  }

  static Map<MarketType, MarketChannelConfig> mergeWithDefaults(
    Map<MarketType, MarketChannelConfig> channels,
  ) {
    final merged = defaultChannels();
    merged.addAll(channels);
    return merged;
  }

  static String _slugify(String value) {
    final sanitized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    if (sanitized.isEmpty) {
      return 'project-${DateTime.now().millisecondsSinceEpoch}';
    }
    final trimmed = sanitized.replaceAll(RegExp(r'^-+|-+$'), '');
    if (trimmed.isEmpty) {
      return 'project-${DateTime.now().millisecondsSinceEpoch}';
    }
    return trimmed;
  }
}
