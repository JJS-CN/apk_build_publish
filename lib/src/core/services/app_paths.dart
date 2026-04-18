import 'dart:io';

class AppPaths {
  const AppPaths._();

  static Directory configDirectory({String appName = 'apk_build_publish'}) {
    final environment = Platform.environment;

    if (Platform.isMacOS) {
      final home = environment['HOME'] ?? '.';
      return Directory('$home/Library/Application Support/$appName');
    }

    if (Platform.isWindows) {
      final appData = environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory('$appData\\$appName');
      }
      final userProfile = environment['USERPROFILE'] ?? '.';
      return Directory('$userProfile\\AppData\\Roaming\\$appName');
    }

    final xdgConfig = environment['XDG_CONFIG_HOME'];
    if (xdgConfig != null && xdgConfig.isNotEmpty) {
      return Directory('$xdgConfig/$appName');
    }

    final home = environment['HOME'] ?? '.';
    return Directory('$home/.config/$appName');
  }

  static File projectsFile({String appName = 'apk_build_publish'}) {
    return File('${configDirectory(appName: appName).path}/projects.json');
  }
}
