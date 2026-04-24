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

class VivoMarketplaceUploader extends ManagedMarketplaceUploader {
  VivoMarketplaceUploader({super.assetResolver});

  @override
  MarketType get market => MarketType.vivo;

  @override
  Future<String> performUpload({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required PublishRequest request,
    required ResolvedPublishAssets assets,
  }) async {
    final credentials = _VivoCredentials.fromChannel(channel);
    final client = _VivoApiClient(credentials);
    final appInfo = await client.queryAppInfo(assets.packageName);
    final status = int.tryParse(appInfo['status']?.toString() ?? '') ?? 0;
    if (status == 2) {
      throw StateError('vivo app is currently under review.');
    }

    String iconSerial = '';
    if (assets.iconFile != null) {
      final result = await client.uploadFile(
        file: assets.iconFile!,
        method: 'app.upload.icon',
        packageName: assets.packageName,
      );
      iconSerial = result['serialnumber']?.toString() ?? '';
    }

    final screenshotSerials = <String>[];
    for (final file in assets.screenshotFiles) {
      final result = await client.uploadFile(
        file: file,
        method: 'app.upload.screenshot',
        packageName: assets.packageName,
      );
      final serial = result['serialnumber']?.toString() ?? '';
      if (serial.isNotEmpty) {
        screenshotSerials.add(serial);
      }
    }

    final apkResult = await client.uploadFile(
      file: assets.apkFile,
      method: 'app.upload.apk.app',
      packageName: assets.packageName,
      includeFileMd5: true,
    );

    await client.publishApp(
      packageName: assets.packageName,
      serialNumber: apkResult['serialnumber']?.toString() ?? '',
      fileMd5: apkResult['fileMd5']?.toString() ?? '',
      versionCode:
          int.tryParse(apkResult['versionCode']?.toString() ?? '') ??
          (assets.versionCode ?? 0),
      releaseNotes: assets.releaseNotes,
      iconSerialNumber: iconSerial,
      screenshotSerialNumbers: screenshotSerials,
    );
    return 'Submitted to vivo App Store.';
  }
}

class _VivoCredentials {
  const _VivoCredentials({
    required this.accessKey,
    required this.accessSecret,
    required this.appId,
  });

  final String accessKey;
  final String accessSecret;
  final String appId;

  factory _VivoCredentials.fromChannel(MarketChannelConfig channel) {
    final fields = ChannelFieldReader(channel.fields);
    return _VivoCredentials(
      accessKey: fields.requireAny(const ['accessKey', 'access_key']),
      accessSecret: fields.requireAny(const ['accessSecret', 'access_secret']),
      appId: fields.requireAny(const ['appId', 'app_id']),
    );
  }
}

class _VivoApiClient {
  _VivoApiClient(this.credentials)
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://developer-api.vivo.com.cn/router/rest',
          contentType: 'application/x-www-form-urlencoded;charset=UTF-8',
        ),
      );

  final _VivoCredentials credentials;
  final Dio _dio;

  Future<Map<String, dynamic>> queryAppInfo(String packageName) async {
    return _post(<String, dynamic>{
      'method': 'app.query.details',
      'packageName': packageName,
    });
  }

  Future<Map<String, dynamic>> uploadFile({
    required File file,
    required String method,
    required String packageName,
    bool includeFileMd5 = false,
  }) async {
    final payload = <String, dynamic>{
      'method': method,
      'packageName': packageName,
      'file': await MultipartFile.fromFile(file.path),
    };
    if (includeFileMd5) {
      payload['fileMd5'] = await fileMd5Hex(file);
    }
    return _post(payload, multipart: true);
  }

  Future<void> publishApp({
    required String packageName,
    required String serialNumber,
    required String fileMd5,
    required int versionCode,
    required String releaseNotes,
    required String iconSerialNumber,
    required List<String> screenshotSerialNumbers,
  }) async {
    await _post(<String, dynamic>{
      'method': 'app.sync.update.app',
      'packageName': packageName,
      'apk': serialNumber,
      'fileMd5': fileMd5,
      'versionCode': versionCode,
      'onlineType': 1,
      'updateDesc': releaseNotes,
      if (iconSerialNumber.isNotEmpty) 'icon': iconSerialNumber,
      if (screenshotSerialNumbers.isNotEmpty)
        'screenshot': screenshotSerialNumbers.join(','),
    });
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> data, {
    bool multipart = false,
  }) async {
    final payload = <String, dynamic>{
      ...data,
      'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
      'access_key': credentials.accessKey,
      'format': 'json',
      'v': '1.0',
      'sign_method': 'HMAC-SHA256',
      'target_app_key': 'developer',
    };

    final signatureEntries =
        payload.entries
            .where((entry) => entry.key != 'file')
            .map((entry) => MapEntry(entry.key, entry.value?.toString() ?? ''))
            .toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    final signatureString = signatureEntries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    payload['sign'] = hmacSha256Hex(
      credentials.accessSecret,
      signatureString,
    ).toLowerCase();

    final response = await _dio.post<Map<String, dynamic>>(
      '',
      data: multipart ? FormData.fromMap(payload) : payload,
      options: Options(
        contentType: multipart
            ? 'multipart/form-data'
            : 'application/x-www-form-urlencoded;charset=UTF-8',
      ),
    );
    final body = response.data ?? const <String, dynamic>{};
    if (body['code'] != 0) {
      throw StateError(body.toString());
    }
    return Map<String, dynamic>.from(
      body['data'] as Map? ?? const <String, dynamic>{},
    );
  }
}
