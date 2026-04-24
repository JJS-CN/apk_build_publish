import 'market_type.dart';

class PublishRequest {
  const PublishRequest({
    this.apkPath,
    this.markets,
    this.dryRun = false,
    this.releaseNotesOverride,
    this.appNameOverride,
    this.iconPath,
    this.screenshotPaths,
    this.includeIcon = true,
    this.includeScreenshots = true,
  });

  final String? apkPath;
  final List<MarketType>? markets;
  final bool dryRun;
  final String? releaseNotesOverride;
  final String? appNameOverride;
  final String? iconPath;
  final List<String>? screenshotPaths;
  final bool includeIcon;
  final bool includeScreenshots;
}
