import 'dart:io';

import '../../models/market_channel_config.dart';
import '../../models/project_config.dart';
import '../../models/publish_request.dart';
import 'apk_badging_reader.dart';
import 'channel_field_reader.dart';
import 'publish_asset_bundle.dart';

class PublishAssetResolver {
  const PublishAssetResolver({ApkBadgingReader? badgingReader})
    : _badgingReader = badgingReader ?? const ApkBadgingReader();

  final ApkBadgingReader _badgingReader;

  Future<ResolvedPublishAssets> resolve({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required PublishRequest request,
    required File apkFile,
  }) async {
    final badging = await _badgingReader.read(apkFile);
    final fieldReader = ChannelFieldReader(channel.fields);
    Directory? tempDirectory;
    File? iconFile;

    if (request.includeIcon) {
      final overridePath = request.iconPath?.trim();
      if (overridePath != null && overridePath.isNotEmpty) {
        final file = File(overridePath);
        if (await file.exists()) {
          iconFile = file;
        }
      }

      if (iconFile == null && badging.resolvedIconEntry != null) {
        tempDirectory = await Directory.systemTemp.createTemp(
          'apk_publish_assets_',
        );
        iconFile = await _extractApkEntry(
          apkFile: apkFile,
          entryPath: badging.resolvedIconEntry!,
          outputDirectory: tempDirectory,
        );
      }
    }

    return ResolvedPublishAssets(
      apkFile: apkFile,
      packageName: _resolvePackageName(project, badging, fieldReader),
      appName: _resolveAppName(project, request, badging),
      versionCode: int.tryParse(badging.versionCode.trim()),
      versionName: badging.versionName.trim(),
      releaseNotes: (request.releaseNotesOverride ?? channel.releaseNotes)
          .trim(),
      iconFile: iconFile,
      screenshotFiles: await _resolveScreenshots(project, request),
      tempDirectory: tempDirectory,
    );
  }

  String _resolvePackageName(
    ProjectConfig project,
    ApkBadgingInfo badging,
    ChannelFieldReader fieldReader,
  ) {
    final override = fieldReader.optionalAny(const [
      'packageName',
      'package_name',
    ]);
    if (override != null && override.isNotEmpty) {
      return override;
    }
    final badgingValue = badging.packageName.trim();
    if (badgingValue.isNotEmpty) {
      return badgingValue;
    }
    return project.packageName.trim();
  }

  String _resolveAppName(
    ProjectConfig project,
    PublishRequest request,
    ApkBadgingInfo badging,
  ) {
    final override = request.appNameOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }

    final label = badging.label.trim();
    if (label.isNotEmpty) {
      return label;
    }
    return project.name.trim();
  }

  Future<List<File>> _resolveScreenshots(
    ProjectConfig project,
    PublishRequest request,
  ) async {
    if (!request.includeScreenshots) {
      return const <File>[];
    }

    final explicitPaths = request.screenshotPaths;
    if (explicitPaths != null && explicitPaths.isNotEmpty) {
      final files = <File>[];
      for (final path in explicitPaths) {
        final file = File(path);
        if (await file.exists()) {
          files.add(file);
        }
      }
      return files;
    }

    final outputDirectory = project.outputDirectory.trim();
    if (outputDirectory.isEmpty) {
      return const <File>[];
    }

    final screenshotDirectory = Directory(
      '$outputDirectory${Platform.pathSeparator}screenshot',
    );
    if (!await screenshotDirectory.exists()) {
      return const <File>[];
    }

    final files = await screenshotDirectory
        .list(followLinks: false)
        .where(
          (entity) =>
              entity is File && _isSupportedImageFile(_fileName(entity)),
        )
        .cast<File>()
        .toList();
    files.sort(
      (left, right) => _fileName(
        left,
      ).toLowerCase().compareTo(_fileName(right).toLowerCase()),
    );
    return files;
  }

  Future<File?> _extractApkEntry({
    required File apkFile,
    required String entryPath,
    required Directory outputDirectory,
  }) async {
    final result = await Process.run('jar', <String>[
      '--extract',
      '--file',
      apkFile.path,
      entryPath,
    ], workingDirectory: outputDirectory.path);
    if (result.exitCode != 0) {
      return null;
    }

    final file = File('${outputDirectory.path}/$entryPath');
    if (!await file.exists()) {
      return null;
    }
    return file;
  }

  bool _isSupportedImageFile(String fileName) {
    final normalized = fileName.toLowerCase();
    return normalized.endsWith('.png') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.webp');
  }

  String _fileName(FileSystemEntity entity) {
    if (entity.uri.pathSegments.isEmpty) {
      return entity.path;
    }
    return entity.uri.pathSegments.last;
  }
}
