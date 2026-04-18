import 'dart:io';

import 'package:apk_build_publish/apk_build_publish.dart';

Future<void> main(List<String> args) async {
  final exitCode = await runCli(args);
  if (exitCode != 0) {
    stderr.writeln('Command failed with exit code $exitCode');
  }
  exit(exitCode);
}
