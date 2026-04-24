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

class OppoMarketplaceUploader extends ManagedMarketplaceUploader {
  OppoMarketplaceUploader({super.assetResolver});

  @override
  MarketType get market => MarketType.oppo;

  @override
  Future<String> performUpload({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required PublishRequest request,
    required ResolvedPublishAssets assets,
  }) async {
    final credentials = _OppoCredentials.fromChannel(channel);
    final client = _OppoApiClient(credentials);
    final appInfo = await client.queryAppInfo(assets.packageName);
    final auditStatus =
        int.tryParse(appInfo['audit_status']?.toString() ?? '') ?? 0;
    if (auditStatus == 1) {
      throw StateError('OPPO app is currently under review.');
    }

    if (assets.iconFile != null) {
      final upload = await client.uploadFile(
        assets.iconFile!,
        _OppoUploadType.photo,
      );
      appInfo['icon_url'] = upload['url'];
    }

    if (assets.screenshotFiles.isNotEmpty) {
      final screenshotUrls = <String>[];
      for (final file in assets.screenshotFiles) {
        final upload = await client.uploadFile(file, _OppoUploadType.photo);
        screenshotUrls.add(upload['url']?.toString() ?? '');
      }
      appInfo['pic_url'] = screenshotUrls
          .where((item) => item.isNotEmpty)
          .join(',');
    }

    final apkUpload = await client.uploadFile(
      assets.apkFile,
      _OppoUploadType.apk,
    );
    apkUpload['cpu_code'] = 0;
    await client.publishApp(
      appInfo: appInfo,
      apkInfo: apkUpload,
      versionCode: assets.versionCode ?? 0,
      releaseNotes: assets.releaseNotes,
    );
    return 'Submitted to OPPO App Market.';
  }
}

class _OppoCredentials {
  const _OppoCredentials({required this.clientId, required this.clientSecret});

  final String clientId;
  final String clientSecret;

  factory _OppoCredentials.fromChannel(MarketChannelConfig channel) {
    final fields = ChannelFieldReader(channel.fields);
    return _OppoCredentials(
      clientId: fields.requireAny(const ['clientId', 'client_id']),
      clientSecret: fields.requireAny(const ['clientSecret', 'client_secret']),
    );
  }
}

enum _OppoUploadType { photo, apk }

class _OppoApiClient {
  _OppoApiClient(this.credentials)
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://oop-openapi-cn.heytapmobi.com',
          contentType: 'application/x-www-form-urlencoded;charset=UTF-8',
        ),
      );

  final _OppoCredentials credentials;
  final Dio _dio;

  String? _accessToken;
  int _expiresAt = 0;

  Future<Map<String, dynamic>> queryAppInfo(String packageName) async {
    return _request(
      'GET',
      '/resource/v1/app/info',
      queryParameters: <String, dynamic>{'pkg_name': packageName},
    );
  }

  Future<Map<String, dynamic>> uploadFile(
    File file,
    _OppoUploadType type,
  ) async {
    final options = await _request('GET', '/resource/v1/upload/get-upload-url');
    final uploader = Dio(BaseOptions(contentType: 'multipart/form-data'));
    final response = await uploader.post<Map<String, dynamic>>(
      options['upload_url'] as String,
      data: FormData.fromMap(<String, dynamic>{
        'type': type.name,
        'sign': options['sign'],
        'file': await MultipartFile.fromFile(file.path),
      }),
    );
    final body = response.data ?? const <String, dynamic>{};
    if (body['errno'] != 0) {
      throw StateError(body.toString());
    }
    return Map<String, dynamic>.from(
      body['data'] as Map? ?? const <String, dynamic>{},
    );
  }

  Future<void> publishApp({
    required Map<String, dynamic> appInfo,
    required Map<String, dynamic> apkInfo,
    required int versionCode,
    required String releaseNotes,
  }) async {
    final payload = json.decode(json.encode(appInfo)) as Map<String, dynamic>;
    payload['apk_url'] = json.encode(<Map<String, dynamic>>[
      <String, dynamic>{
        'url': apkInfo['url'],
        'md5': apkInfo['md5'],
        'cpu_code': apkInfo['cpu_code'] ?? 0,
      },
    ]);
    payload.removeWhere((key, value) => value == null);

    await _request(
      'POST',
      '/resource/v1/app/upd',
      data: <String, dynamic>{
        'pkg_name': payload['pkg_name'],
        'version_code': versionCode,
        'online_type': 1,
        'apk_url': payload['apk_url'],
        'app_name': payload['app_name'],
        'second_category_id': payload['second_category_id'],
        'third_category_id': payload['third_category_id'],
        'summary': payload['summary'],
        'detail_desc': payload['detail_desc'],
        'update_desc': releaseNotes.isEmpty
            ? payload['update_desc']
            : releaseNotes,
        'privacy_source_url': payload['privacy_source_url'],
        'icon_url': payload['icon_url'],
        'pic_url': payload['pic_url'],
        'test_desc': payload['test_desc'],
        'copyright_url': payload['copyright_url'],
        'icp_url': payload['icp_url'],
        'special_url': payload['special_url'],
        'special_file_url': payload['special_file_url'],
        'business_username': payload['business_username'],
        'business_email': payload['business_email'],
        'business_mobile': payload['business_mobile'],
      },
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? data,
  }) async {
    await _ensureToken();
    final requestData = <String, dynamic>{
      'timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'access_token': _accessToken,
      ...?queryParameters,
      ...?data,
    }..removeWhere((key, value) => value == null);

    final signaturePayload = requestData.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final signatureString = signaturePayload
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    requestData['api_sign'] = hmacSha256Hex(
      credentials.clientSecret,
      signatureString,
    ).toLowerCase();

    final response = await _dio.request<Map<String, dynamic>>(
      path,
      queryParameters: method == 'GET' ? requestData : null,
      data: method == 'POST' ? requestData : null,
      options: Options(method: method),
    );
    final body = response.data ?? const <String, dynamic>{};
    if (body['errno'] != 0) {
      throw StateError(body.toString());
    }
    return Map<String, dynamic>.from(body['data'] as Map? ?? body);
  }

  Future<void> _ensureToken() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_accessToken != null && now < _expiresAt) {
      return;
    }

    final response = await Dio().get<Map<String, dynamic>>(
      'https://oop-openapi-cn.heytapmobi.com/developer/v1/token',
      queryParameters: <String, dynamic>{
        'client_id': credentials.clientId,
        'client_secret': credentials.clientSecret,
      },
    );
    final body = response.data ?? const <String, dynamic>{};
    final data = Map<String, dynamic>.from(
      body['data'] as Map? ?? const <String, dynamic>{},
    );
    _accessToken = data['access_token']?.toString();
    final expireIn = int.tryParse(data['expire_in']?.toString() ?? '') ?? 0;
    _expiresAt =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) + expireIn - 60;
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw StateError('OPPO token request failed.');
    }
  }
}
