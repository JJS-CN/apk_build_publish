import 'dart:io';

import 'package:flutter/services.dart';

class ToolBundle {
  const ToolBundle._();

  static final Map<String, Future<File>> _extractedTools =
      <String, Future<File>>{};

  static Future<File> apktool([Directory? root]) async {
    return _resolveTool(
      fileName: 'apktool.jar',
      assetPath: 'tools/apktool.jar',
      root: root,
    );
  }

  static Future<File> vasDolly([Directory? root]) async {
    return _resolveTool(
      fileName: 'VasDolly.jar',
      assetPath: 'tools/VasDolly.jar',
      root: root,
    );
  }

  static Future<File> _resolveTool({
    required String fileName,
    required String assetPath,
    Directory? root,
  }) async {
    final localFile = File(
      '${(root ?? Directory.current).path}/tools/$fileName',
    );
    if (await localFile.exists()) {
      return localFile;
    }

    return _extractedTools.putIfAbsent(
      fileName,
      () => _extractAsset(assetPath: assetPath, fileName: fileName),
    );
  }

  static Future<File> _extractAsset({
    required String assetPath,
    required String fileName,
  }) async {
    final ByteData byteData = await rootBundle.load(assetPath);
    final Uint8List bytes = byteData.buffer.asUint8List();

    final toolsDir = Directory(
      '${Directory.systemTemp.path}/apk_build_publish_tools',
    );
    await toolsDir.create(recursive: true);

    final outputFile = File('${toolsDir.path}/$fileName');
    await outputFile.writeAsBytes(bytes, flush: true);
    return outputFile;
  }
}
