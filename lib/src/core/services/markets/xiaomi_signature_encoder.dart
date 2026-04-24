import 'dart:convert';

import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';

class XiaomiSignatureEncoder {
  const XiaomiSignatureEncoder();

  Future<String> encode(String publicPem, Map<String, dynamic> payload) async {
    final publicKey = RSAKeyParser().parse(publicPem) as RSAPublicKey;
    final encrypter = Encrypter(RSA(publicKey: publicKey));
    final sourceBytes = utf8.encode(json.encode(payload));
    const maxChunkLength = 117;
    final encryptedBytes = <int>[];

    for (var index = 0; index < sourceBytes.length; index += maxChunkLength) {
      final end = (index + maxChunkLength < sourceBytes.length)
          ? index + maxChunkLength
          : sourceBytes.length;
      encryptedBytes.addAll(
        encrypter.encryptBytes(sourceBytes.sublist(index, end)).bytes,
      );
    }

    return encryptedBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
