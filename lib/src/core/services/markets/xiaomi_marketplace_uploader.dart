import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/market_channel_config.dart';
import '../../models/market_type.dart';
import '../../models/project_config.dart';
import '../../models/publish_request.dart';
import 'channel_field_reader.dart';
import 'managed_marketplace_uploader.dart';
import 'market_crypto_utils.dart';
import 'publish_asset_bundle.dart';
import 'xiaomi_signature_encoder.dart';

class XiaomiMarketplaceUploader extends ManagedMarketplaceUploader {
  XiaomiMarketplaceUploader({
    XiaomiSignatureEncoder? signatureEncoder,
    super.assetResolver,
  }) : _signatureEncoder = signatureEncoder ?? const XiaomiSignatureEncoder();

  final XiaomiSignatureEncoder _signatureEncoder;

  @override
  MarketType get market => MarketType.xiaomi;

  @override
  Future<String> performUpload({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required PublishRequest request,
    required ResolvedPublishAssets assets,
  }) async {
    final credentials = _XiaomiCredentials.fromChannel(channel);
    final client = _XiaomiApiClient(credentials, _signatureEncoder);
    final packageInfo = await client.queryPackageInfo(assets.packageName);
    final appName = packageInfo['appName']?.toString().trim().isNotEmpty == true
        ? packageInfo['appName'].toString().trim()
        : assets.appName;

    await client.publish(
      packageName: assets.packageName,
      appName: appName,
      releaseNotes: assets.releaseNotes,
      apkFile: assets.apkFile,
      iconFile: assets.iconFile,
      screenshotFiles: assets.screenshotFiles,
    );
    return 'Submitted to Xiaomi App Store.';
  }
}

class _XiaomiCredentials {
  const _XiaomiCredentials({
    required this.userName,
    required this.publicPem,
    required this.privateKey,
  });

  final String userName;
  final String publicPem;
  final String privateKey;

  factory _XiaomiCredentials.fromChannel(MarketChannelConfig channel) {
    final fields = ChannelFieldReader(channel.fields);
    return _XiaomiCredentials(
      userName: fields.requireAny(const ['userName', 'user_name']),
      publicPem: fields.requireAny(const ['publicPem', 'public_pem']),
      privateKey: fields.requireAny(const ['privateKey', 'private_key']),
    );
  }
}

class _XiaomiApiClient {
  _XiaomiApiClient(this.credentials, this.signatureEncoder)
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://api.developer.xiaomi.com/devupload',
          contentType: 'multipart/form-data',
        ),
      );

  final _XiaomiCredentials credentials;
  final XiaomiSignatureEncoder signatureEncoder;
  final Dio _dio;

  Future<Map<String, dynamic>> queryPackageInfo(String packageName) async {
    final requestData = <String, dynamic>{
      'packageName': packageName,
      'userName': credentials.userName,
    };
    final response = await _postSigned(
      '/dev/query',
      requestData: requestData,
      payload: <String, dynamic>{'RequestData': json.encode(requestData)},
    );
    return Map<String, dynamic>.from(
      response['packageInfo'] as Map? ?? const <String, dynamic>{},
    );
  }

  Future<void> publish({
    required String packageName,
    required String appName,
    required String releaseNotes,
    required File apkFile,
    required File? iconFile,
    required List<File> screenshotFiles,
  }) async {
    final requestData = <String, dynamic>{
      'userName': credentials.userName,
      'synchroType': 1,
      'appInfo': <String, dynamic>{
        'appName': appName,
        'packageName': packageName,
        if (releaseNotes.isNotEmpty) 'updateDesc': releaseNotes,
      },
    };

    final payload = <String, dynamic>{'RequestData': json.encode(requestData)};
    final signatureItems = <Map<String, String>>[];

    void addSignatureField(String name, String value) {
      signatureItems.add(<String, String>{
        'name': name,
        'hash': md5HexFromBytes(utf8.encode(value)),
      });
    }

    addSignatureField('RequestData', payload['RequestData'] as String);

    payload['apk'] = await MultipartFile.fromFile(apkFile.path);
    signatureItems.add(<String, String>{
      'name': 'apk',
      'hash': await fileMd5Hex(apkFile),
    });

    if (iconFile != null) {
      payload['icon'] = await MultipartFile.fromFile(iconFile.path);
      signatureItems.add(<String, String>{
        'name': 'icon',
        'hash': await fileMd5Hex(iconFile),
      });
    }

    for (var index = 0; index < screenshotFiles.length; index++) {
      final file = screenshotFiles[index];
      final fieldName = 'screenshot_${index + 1}';
      payload[fieldName] = await MultipartFile.fromFile(file.path);
      signatureItems.add(<String, String>{
        'name': fieldName,
        'hash': await fileMd5Hex(file),
      });
    }

    final signature = await signatureEncoder.encode(
      credentials.publicPem,
      <String, dynamic>{
        'password': credentials.privateKey,
        'sig': signatureItems,
      },
    );
    payload['SIG'] = signature;

    final response = await _dio.post<Map<String, dynamic>>(
      '/dev/push',
      data: FormData.fromMap(payload),
    );
    final body = response.data ?? const <String, dynamic>{};
    if (body['result'] != 0) {
      throw StateError(body.toString());
    }
  }

  Future<Map<String, dynamic>> _postSigned(
    String path, {
    required Map<String, dynamic> requestData,
    required Map<String, dynamic> payload,
  }) async {
    final signature = await signatureEncoder.encode(
      credentials.publicPem,
      <String, dynamic>{
        'password': credentials.privateKey,
        'sig': <Map<String, String>>[
          <String, String>{
            'name': 'RequestData',
            'hash': md5HexFromBytes(utf8.encode(json.encode(requestData))),
          },
        ],
      },
    );
    payload['SIG'] = signature;

    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(payload),
    );
    final body = response.data ?? const <String, dynamic>{};
    if (body['result'] != 0) {
      throw StateError(body.toString());
    }
    return body;
  }
}
