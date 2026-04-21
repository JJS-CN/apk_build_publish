import 'dart:io';

import '../models/project_config.dart';
import 'tool_bundle.dart';

typedef ApkPackageReader = Future<String?> Function(File apkFile);

class BaseApkLookupResult {
  const BaseApkLookupResult({
    required this.matchedFile,
    required this.message,
    required this.searchedDirectory,
  });

  final File? matchedFile;
  final String message;
  final String searchedDirectory;

  bool get found => matchedFile != null;
}

class BaseApkMatcher {
  const BaseApkMatcher._();

  static Future<File?> findBestMatch(
    ProjectConfig project, {
    String? explicitPath,
    ApkPackageReader? packageReader,
  }) async {
    final result = await lookup(
      project,
      explicitPath: explicitPath,
      packageReader: packageReader,
    );
    return result.matchedFile;
  }

  static Future<BaseApkLookupResult> lookup(
    ProjectConfig project, {
    String? explicitPath,
    ApkPackageReader? packageReader,
  }) async {
    try {
      final directPath = explicitPath?.trim();
      if (directPath != null && directPath.isNotEmpty) {
        final directFile = File(directPath);
        if (await directFile.exists()) {
          return BaseApkLookupResult(
            matchedFile: directFile,
            message: directFile.path,
            searchedDirectory: directFile.parent.path,
          );
        }
      }

      final configuredPath = project.basePackagePath.trim();
      if (configuredPath.isEmpty) {
        return const BaseApkLookupResult(
          matchedFile: null,
          message: '未配置基础包目录',
          searchedDirectory: '',
        );
      }

      final file = File(configuredPath);
      if (await file.exists()) {
        return BaseApkLookupResult(
          matchedFile: file,
          message: file.path,
          searchedDirectory: file.parent.path,
        );
      }

      final directory = Directory(configuredPath);
      if (!await directory.exists()) {
        return BaseApkLookupResult(
          matchedFile: null,
          message: '目录不存在',
          searchedDirectory: configuredPath,
        );
      }

      final apktoolFile = await ToolBundle.apktool();
      if (!await apktoolFile.exists()) {
        return BaseApkLookupResult(
          matchedFile: null,
          message: '缺少 apktool.jar',
          searchedDirectory: configuredPath,
        );
      }

      final baseApkFiles = await directory
          .list(recursive: true, followLinks: false)
          .where(
            (entity) =>
                entity is File &&
                _fileName(entity).toLowerCase().endsWith('base.apk'),
          )
          .cast<File>()
          .toList();

      if (baseApkFiles.isEmpty) {
        return BaseApkLookupResult(
          matchedFile: null,
          message: '未找到 *base.apk',
          searchedDirectory: configuredPath,
        );
      }

      final reader = packageReader ?? _readPackageNameWithApktool;
      final packageName = project.packageName.trim();

      for (final candidate in baseApkFiles) {
        final decodedPackageName = await reader(candidate);
        if (decodedPackageName == packageName) {
          return BaseApkLookupResult(
            matchedFile: candidate,
            message: candidate.path,
            searchedDirectory: configuredPath,
          );
        }
      }

      return BaseApkLookupResult(
        matchedFile: null,
        message: '未找到匹配包名的 base.apk',
        searchedDirectory: configuredPath,
      );
    } on FileSystemException {
      return BaseApkLookupResult(
        matchedFile: null,
        message: '目录无访问权限，请重新选择基础包目录',
        searchedDirectory: project.basePackagePath,
      );
    }
  }

  static Future<String?> _readPackageNameWithApktool(File apkFile) async {
    final apktoolFile = await ToolBundle.apktool();
    final tempDir = await Directory.systemTemp.createTemp('apk_build_publish_');
    final outputDir = Directory('${tempDir.path}/decoded');
    final tempApkFile = File('${tempDir.path}/${_fileName(apkFile)}');

    try {
      await apkFile.copy(tempApkFile.path);
      final result = await Process.run('java', <String>[
        '-jar',
        apktoolFile.path,
        'd',
        '-f',
        '-s',
        '-o',
        outputDir.path,
        tempApkFile.path,
      ]);

      if (result.exitCode != 0) {
        return null;
      }

      final manifestFile = File('${outputDir.path}/AndroidManifest.xml');
      if (!await manifestFile.exists()) {
        return null;
      }

      final manifest = await manifestFile.readAsString();
      final match = RegExp(r'package="([^"]+)"').firstMatch(manifest);
      return match?.group(1);
    } catch (_) {
      return null;
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  static String _fileName(FileSystemEntity entity) {
    if (entity.uri.pathSegments.isEmpty) {
      return entity.path;
    }
    return entity.uri.pathSegments.last;
  }
}
