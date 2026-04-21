import 'dart:io';

import 'package:apk_build_publish/src/core/models/market_channel_config.dart';
import 'package:apk_build_publish/src/core/models/market_type.dart';
import 'package:apk_build_publish/src/core/models/project_config.dart';
import 'package:apk_build_publish/src/core/models/publish_request.dart';
import 'package:apk_build_publish/src/core/services/apk_publish_service.dart';
import 'package:apk_build_publish/src/core/services/base_apk_matcher.dart';
import 'package:apk_build_publish/src/core/services/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectStore', () {
    test('persists and restores project config', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_publish_test');
      final store = ProjectStore(
        storageFile: File('${tempDir.path}/projects.json'),
      );
      final project =
          ProjectConfig.create(
            name: 'demo',
            packageName: 'com.example.demo',
            basePackagePath: '/tmp/apk',
            outputDirectory: '/tmp/output',
          ).copyWith(
            channels: {
              ...ProjectConfig.defaultChannels(),
              MarketType.huawei: const MarketChannelConfig(
                market: MarketType.huawei,
                enabled: true,
                endpoint: 'https://example.com/upload',
              ),
            },
          );

      await store.saveProject(project);
      final loaded = await store.loadAll();

      expect(loaded, hasLength(1));
      expect(loaded.first.name, 'demo');
      expect(loaded.first.packageName, 'com.example.demo');
      expect(loaded.first.channels[MarketType.huawei]?.enabled, isTrue);
    });
  });

  group('ApkPublishService', () {
    test('supports dry run with enabled markets', () async {
      final service = ApkPublishService();
      final project =
          ProjectConfig.create(
            name: 'dry-run',
            packageName: 'com.example.dryrun',
            basePackagePath: '/missing.apk',
            outputDirectory: '/tmp/output',
          ).copyWith(
            channels: {
              ...ProjectConfig.defaultChannels(),
              MarketType.huawei: const MarketChannelConfig(
                market: MarketType.huawei,
                enabled: true,
              ),
              MarketType.xiaomi: const MarketChannelConfig(
                market: MarketType.xiaomi,
                enabled: true,
              ),
            },
          );

      final result = await service.publishProject(
        project: project,
        request: const PublishRequest(dryRun: true),
      );

      expect(result.isSuccess, isTrue);
      expect(result.results, hasLength(2));
    });
  });

  group('BaseApkMatcher', () {
    test('matches base.apk files by decoded package name', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_matcher_dir');
      final matchedDir = Directory('${tempDir.path}/com.example.directory');
      final unmatchedDir = Directory('${tempDir.path}/com.example.other');
      await matchedDir.create(recursive: true);
      await unmatchedDir.create(recursive: true);

      final matchedBaseApk = File('${matchedDir.path}/base.apk');
      final unmatchedBaseApk = File('${unmatchedDir.path}/base.apk');
      final ignoredApk = File('${matchedDir.path}/feature.apk');
      await matchedBaseApk.writeAsString('matched');
      await unmatchedBaseApk.writeAsString('other');
      await ignoredApk.writeAsString('ignored');

      final project = ProjectConfig.create(
        name: 'directory-demo',
        packageName: 'com.example.directory',
        basePackagePath: tempDir.path,
        outputDirectory: '/tmp/output',
      );

      final result = await BaseApkMatcher.lookup(
        project,
        packageReader: (apkFile) async {
          if (apkFile.path == matchedBaseApk.path) {
            return 'com.example.directory';
          }
          return 'com.example.other';
        },
      );

      expect(result.found, isTrue);
      expect(result.matchedFile?.path, matchedBaseApk.path);
    });
  });
}
