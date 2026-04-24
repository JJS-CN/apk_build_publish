import 'dart:io';

class ApkBadgingInfo {
  const ApkBadgingInfo({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.label,
    required this.resolvedIconEntry,
  });

  final String packageName;
  final String versionCode;
  final String versionName;
  final String label;
  final String? resolvedIconEntry;
}

class ApkBadgingReader {
  const ApkBadgingReader();

  Future<ApkBadgingInfo> read(File apkFile) async {
    final result = await Process.run('aapt', <String>[
      'dump',
      'badging',
      apkFile.path,
    ]);
    if (result.exitCode != 0) {
      final errorText = (result.stderr?.toString() ?? '').trim();
      throw StateError(
        errorText.isEmpty ? 'Failed to read apk badging.' : errorText,
      );
    }

    final output = result.stdout.toString();
    final packageMatch = RegExp(
      r"package: name='([^']+)' versionCode='([^']*)' versionName='([^']*)'",
    ).firstMatch(output);
    if (packageMatch == null) {
      throw const FormatException('Unable to parse package info from aapt.');
    }

    return ApkBadgingInfo(
      packageName: packageMatch.group(1) ?? '',
      versionCode: packageMatch.group(2) ?? '',
      versionName: packageMatch.group(3) ?? '',
      label: _readLabel(output),
      resolvedIconEntry: _readResolvedIconEntry(output),
    );
  }

  String _readLabel(String output) {
    final localizedMatch = RegExp(
      r"application-label-[^:]+:'([^']+)'",
    ).firstMatch(output);
    if (localizedMatch != null) {
      return localizedMatch.group(1) ?? '';
    }

    final defaultMatch = RegExp(
      r"application-label:'([^']+)'",
    ).firstMatch(output);
    if (defaultMatch != null) {
      return defaultMatch.group(1) ?? '';
    }

    final applicationMatch = RegExp(
      r"application:.* label='([^']*)'",
    ).firstMatch(output);
    return applicationMatch?.group(1) ?? '';
  }

  String? _readResolvedIconEntry(String output) {
    final densityMatches = RegExp(
      r"application-icon-(\d+):'([^']+)'",
    ).allMatches(output).toList();
    if (densityMatches.isNotEmpty) {
      densityMatches.sort((left, right) {
        final leftDensity = int.tryParse(left.group(1) ?? '') ?? 0;
        final rightDensity = int.tryParse(right.group(1) ?? '') ?? 0;
        return rightDensity.compareTo(leftDensity);
      });
      return densityMatches.first.group(2);
    }

    final applicationMatch = RegExp(
      r"application:.* icon='([^']+)'",
    ).firstMatch(output);
    return applicationMatch?.group(1);
  }
}
