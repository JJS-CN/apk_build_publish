import 'dart:io';

class ResolvedPublishAssets {
  ResolvedPublishAssets({
    required this.apkFile,
    required this.packageName,
    required this.appName,
    required this.versionCode,
    required this.versionName,
    required this.releaseNotes,
    required this.iconFile,
    required this.screenshotFiles,
    required this.tempDirectory,
  });

  final File apkFile;
  final String packageName;
  final String appName;
  final int? versionCode;
  final String versionName;
  final String releaseNotes;
  final File? iconFile;
  final List<File> screenshotFiles;
  final Directory? tempDirectory;

  Future<void> dispose() async {
    final dir = tempDirectory;
    if (dir != null && await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
