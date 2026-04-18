import 'market_type.dart';

class PublishRequest {
  const PublishRequest({
    this.apkPath,
    this.markets,
    this.dryRun = false,
    this.releaseNotesOverride,
  });

  final String? apkPath;
  final List<MarketType>? markets;
  final bool dryRun;
  final String? releaseNotesOverride;
}
