import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

String md5HexFromBytes(List<int> bytes) {
  return md5.convert(bytes).toString();
}

Future<String> fileMd5Hex(File file) async {
  return md5HexFromBytes(await file.readAsBytes());
}

String hmacSha256Hex(String secret, String payload) {
  final hmac = Hmac(sha256, utf8.encode(secret));
  return hmac.convert(utf8.encode(payload)).toString();
}
