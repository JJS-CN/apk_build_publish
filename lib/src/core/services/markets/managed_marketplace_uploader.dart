import 'dart:io';

import '../../models/market_channel_config.dart';
import '../../models/market_type.dart';
import '../../models/project_config.dart';
import '../../models/publish_request.dart';
import '../../models/publish_result.dart';
import '../marketplace_uploader.dart';
import 'publish_asset_bundle.dart';
import 'publish_asset_resolver.dart';

abstract class ManagedMarketplaceUploader extends MarketplaceUploader {
  ManagedMarketplaceUploader({PublishAssetResolver? assetResolver})
    : _assetResolver = assetResolver ?? const PublishAssetResolver();

  final PublishAssetResolver _assetResolver;

  MarketType get market;

  @override
  Future<MarketPublishResult> upload({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required File apkFile,
    required PublishRequest request,
  }) async {
    final startedAt = DateTime.now();
    if (request.dryRun) {
      return MarketPublishResult(
        market: market,
        success: true,
        message: 'Dry run completed for ${market.displayName}.',
        duration: DateTime.now().difference(startedAt),
      );
    }

    ResolvedPublishAssets? assets;
    try {
      assets = await _assetResolver.resolve(
        project: project,
        channel: channel,
        request: request,
        apkFile: apkFile,
      );
      final message = await performUpload(
        project: project,
        channel: channel,
        request: request,
        assets: assets,
      );
      return MarketPublishResult(
        market: market,
        success: true,
        message: message,
        duration: DateTime.now().difference(startedAt),
      );
    } catch (error) {
      return MarketPublishResult(
        market: market,
        success: false,
        message: error.toString(),
        duration: DateTime.now().difference(startedAt),
      );
    } finally {
      await assets?.dispose();
    }
  }

  Future<String> performUpload({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required PublishRequest request,
    required ResolvedPublishAssets assets,
  });
}
