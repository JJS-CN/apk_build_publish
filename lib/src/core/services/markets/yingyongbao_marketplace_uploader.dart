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

class YingyongbaoMarketplaceUploader extends ManagedMarketplaceUploader {
  YingyongbaoMarketplaceUploader({super.assetResolver});

  @override
  MarketType get market => MarketType.tencent;

  @override
  Future<String> performUpload({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required PublishRequest request,
    required ResolvedPublishAssets assets,
  }) async {
    final credentials = _YingyongbaoCredentials.fromChannel(channel);
    final client = _YingyongbaoApiClient(credentials);
    final updateStatus = await client.queryUpdateStatus(assets.packageName);
    if (updateStatus['audit_status']?.toString() == '1') {
      throw StateError('Yingyongbao app is currently under review.');
    }

    final apkUpload = await client.uploadFile(
      file: assets.apkFile,
      fileType: 'apk',
      packageName: assets.packageName,
    );

    String iconSerial = '';
    if (assets.iconFile != null) {
      final iconUpload = await client.uploadFile(
        file: assets.iconFile!,
        fileType: 'img',
        packageName: assets.packageName,
      );
      iconSerial = iconUpload['serial_number']?.toString() ?? '';
    }

    final screenshotSerials = <String>[];
    for (final file in assets.screenshotFiles) {
      final upload = await client.uploadFile(
        file: file,
        fileType: 'img',
        packageName: assets.packageName,
      );
      final serial = upload['serial_number']?.toString() ?? '';
      if (serial.isNotEmpty) {
        screenshotSerials.add(serial);
      }
    }

    await client.publishApp(
      packageName: assets.packageName,
      apkSerialNumber: apkUpload['serial_number']?.toString() ?? '',
      apkMd5: apkUpload['file_md5']?.toString() ?? '',
      releaseNotes: assets.releaseNotes,
      iconSerialNumber: iconSerial,
      screenshotSerialNumbers: screenshotSerials,
    );
    return 'Submitted to Yingyongbao.';
  }
}

class _YingyongbaoCredentials {
  const _YingyongbaoCredentials({
    required this.appId,
    required this.userId,
    required this.secretKey,
  });

  final String appId;
  final String userId;
  final String secretKey;

  factory _YingyongbaoCredentials.fromChannel(MarketChannelConfig channel) {
    final fields = ChannelFieldReader(channel.fields);
    return _YingyongbaoCredentials(
      appId: fields.requireAny(const ['appId', 'app_id']),
      userId: fields.requireAny(const ['userId', 'user_id']),
      secretKey: fields.requireAny(const ['secretKey', 'secret_key']),
    );
  }
}

class _YingyongbaoApiClient {
  _YingyongbaoApiClient(this.credentials)
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://p.open.qq.com/open_file/developer_api',
          contentType: 'application/x-www-form-urlencoded',
        ),
      );

  final _YingyongbaoCredentials credentials;
  final Dio _dio;

  Future<Map<String, dynamic>> queryUpdateStatus(String packageName) async {
    return _post('/query_app_update_status', <String, dynamic>{
      'pkg_name': packageName,
      'app_id': credentials.appId,
    });
  }

  Future<Map<String, dynamic>> uploadFile({
    required File file,
    required String fileType,
    required String packageName,
  }) async {
    final uploadInfo = await _post('/get_file_upload_info', <String, dynamic>{
      'pkg_name': packageName,
      'app_id': credentials.appId,
      'file_name': _fileName(file),
      'file_type': fileType,
    }, packageName: null);

    final uploader = Dio(BaseOptions(contentType: 'application/octet-stream'));
    await uploader.put(
      uploadInfo['pre_sign_url'] as String,
      data: await file.readAsBytes(),
    );

    return <String, dynamic>{...uploadInfo, 'file_md5': await fileMd5Hex(file)};
  }

  Future<void> publishApp({
    required String packageName,
    required String apkSerialNumber,
    required String apkMd5,
    required String releaseNotes,
    required String iconSerialNumber,
    required List<String> screenshotSerialNumbers,
  }) async {
    await _post('/update_app', <String, dynamic>{
      'pkg_name': packageName,
      'app_id': credentials.appId,
      'apk32_file_serial_number': apkSerialNumber,
      'apk32_file_md5': apkMd5,
      'feature': releaseNotes,
      'deploy_type': 1,
      if (iconSerialNumber.isNotEmpty)
        'icon_file_serial_number': iconSerialNumber,
      if (screenshotSerialNumbers.isNotEmpty)
        'snapshots_file_serial_number': screenshotSerialNumbers.join('|'),
    });
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data, {
    String? packageName,
  }) async {
    final payload = <String, dynamic>{
      'timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'user_id': credentials.userId,
      ...data,
    }..removeWhere((key, value) => value == null);

    if (packageName != null && packageName.isNotEmpty) {
      payload['pkg_name'] = packageName;
    }

    final sorted = payload.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final signatureText = sorted
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    payload['sign'] = hmacSha256Hex(credentials.secretKey, signatureText);

    final response = await _dio.post<Map<String, dynamic>>(path, data: payload);
    final body = response.data ?? const <String, dynamic>{};
    if (body['ret'] != 0) {
      throw StateError(body.toString());
    }
    return Map<String, dynamic>.from(body);
  }

  String _fileName(File file) {
    if (file.uri.pathSegments.isEmpty) {
      return file.path;
    }
    return file.uri.pathSegments.last;
  }
}
