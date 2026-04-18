import 'dart:io';

import '../models/market_channel_config.dart';
import '../models/market_type.dart';
import '../models/project_config.dart';
import '../models/publish_request.dart';
import '../models/publish_result.dart';
import 'marketplace_registry.dart';

class ApkPublishService {
  ApkPublishService({MarketplaceRegistry? registry})
    : _registry = registry ?? MarketplaceRegistry.defaultRegistry();

  final MarketplaceRegistry _registry;

  Future<PublishResult> publishProject({
    required ProjectConfig project,
    required PublishRequest request,
    void Function(String message)? onLog,
  }) async {
    final targetMarkets = _resolveTargetMarkets(project, request);
    if (targetMarkets.isEmpty) {
      throw StateError(
        'No market selected. Enable a market or pass --markets.',
      );
    }

    final apkFile = await _resolveApkFile(project, request);
    if (!request.dryRun && !await apkFile.exists()) {
      throw FileSystemException('APK file not found', apkFile.path);
    }

    final results = <MarketPublishResult>[];
    for (final market in targetMarkets) {
      final channel =
          project.channels[market] ?? MarketChannelConfig(market: market);
      onLog?.call('Uploading to ${market.displayName}...');
      final uploader = _registry[market];
      if (uploader == null) {
        results.add(
          MarketPublishResult(
            market: market,
            success: false,
            message: 'No uploader registered for ${market.displayName}.',
          ),
        );
        continue;
      }

      final result = await uploader.upload(
        project: project,
        channel: channel,
        apkFile: apkFile,
        request: request,
      );
      onLog?.call(
        '[${result.success ? 'OK' : 'FAIL'}] ${market.displayName}: ${result.message}',
      );
      results.add(result);
    }

    return PublishResult(
      projectId: project.id,
      apkPath: apkFile.path,
      results: results,
    );
  }

  List<MarketType> _resolveTargetMarkets(
    ProjectConfig project,
    PublishRequest request,
  ) {
    final requestedMarkets = request.markets;
    if (requestedMarkets != null && requestedMarkets.isNotEmpty) {
      return requestedMarkets;
    }
    return project.enabledMarkets;
  }

  Future<File> _resolveApkFile(
    ProjectConfig project,
    PublishRequest request,
  ) async {
    final explicitPath = request.apkPath?.trim();
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return File(explicitPath);
    }

    final configuredPath = project.basePackagePath.trim();
    if (configuredPath.isEmpty) {
      return File(configuredPath);
    }

    final file = File(configuredPath);
    if (await file.exists()) {
      return file;
    }

    final directory = Directory(configuredPath);
    if (!await directory.exists()) {
      return file;
    }

    final apkFiles = await directory
        .list(recursive: true, followLinks: false)
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.apk'),
        )
        .cast<File>()
        .toList();

    if (apkFiles.isEmpty) {
      return File(configuredPath);
    }

    final packageName = project.packageName.trim().toLowerCase();
    final matchedFiles = packageName.isEmpty
        ? apkFiles
        : apkFiles.where((candidate) {
            final fileName = candidate.uri.pathSegments.isEmpty
                ? candidate.path.toLowerCase()
                : candidate.uri.pathSegments.last.toLowerCase();
            return fileName.contains(packageName);
          }).toList();

    final candidates = matchedFiles.isNotEmpty ? matchedFiles : apkFiles;
    candidates.sort(
      (left, right) =>
          right.statSync().modified.compareTo(left.statSync().modified),
    );
    return candidates.first;
  }
}
