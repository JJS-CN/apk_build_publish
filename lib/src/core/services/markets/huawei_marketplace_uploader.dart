import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/market_channel_config.dart';
import '../../models/market_type.dart';
import '../../models/project_config.dart';
import '../../models/publish_request.dart';
import 'channel_field_reader.dart';
import 'managed_marketplace_uploader.dart';
import 'publish_asset_bundle.dart';

class HuaweiMarketplaceUploader extends ManagedMarketplaceUploader {
  HuaweiMarketplaceUploader({super.assetResolver});

  @override
  MarketType get market => MarketType.huawei;

  @override
  Future<String> performUpload({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required PublishRequest request,
    required ResolvedPublishAssets assets,
  }) async {
    final credentials = _HuaweiCredentials.fromChannel(channel);
    final client = _HuaweiApiClient(credentials);

    final appInfo = await client.queryAppInfo();
    final releaseState = appInfo['releaseState'] as int? ?? -1;
    if (releaseState == 4 || releaseState == 5 || releaseState == 12) {
      throw StateError('Huawei app is currently under review.');
    }

    if (assets.releaseNotes.isNotEmpty) {
      await client.publishLanguageInfo(newFeatures: assets.releaseNotes);
    }
    if (assets.iconFile != null) {
      await client.publishIconFile(assets.iconFile!);
    }
    if (assets.screenshotFiles.isNotEmpty) {
      await client.publishScreenshotFiles(assets.screenshotFiles);
    }
    await client.publishApkFile(assets.apkFile);
    await client.submitApp();
    return 'Submitted to Huawei AppGallery.';
  }
}

class _HuaweiCredentials {
  const _HuaweiCredentials({
    required this.appId,
    required this.clientId,
    required this.clientSecret,
  });

  final String appId;
  final String clientId;
  final String clientSecret;

  factory _HuaweiCredentials.fromChannel(MarketChannelConfig channel) {
    final fields = ChannelFieldReader(channel.fields);
    return _HuaweiCredentials(
      appId: fields.requireAny(const ['appId', 'app_id']),
      clientId: fields.requireAny(const ['clientId', 'client_id']),
      clientSecret: fields.requireAny(const ['clientSecret', 'client_secret']),
    );
  }
}

class _HuaweiApiClient {
  _HuaweiApiClient(this.credentials)
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://connect-api.cloud.huawei.com/api',
          contentType: 'application/json;charset=UTF-8',
        ),
      );

  final _HuaweiCredentials credentials;
  final Dio _dio;

  String? _accessToken;
  int _expiresAt = 0;

  Future<Map<String, dynamic>> queryAppInfo() async {
    final response = await _request(
      'GET',
      '/publish/v2/app-info',
      queryParameters: <String, dynamic>{'appId': credentials.appId},
    );
    return response['appInfo'] as Map<String, dynamic>? ?? const {};
  }

  Future<void> publishLanguageInfo({required String newFeatures}) async {
    await _request(
      'PUT',
      '/publish/v2/app-language-info',
      queryParameters: <String, dynamic>{
        'releaseType': 1,
        'appId': credentials.appId,
      },
      data: <String, dynamic>{'lang': 'zh-CN', 'newFeatures': newFeatures},
    );
  }

  Future<void> publishIconFile(File file) async {
    final objectId = await _uploadFileToObs(file);
    await _publishFileInfo(
      fileType: 0,
      files: <Map<String, dynamic>>[
        <String, dynamic>{'fileDestUrl': objectId},
      ],
    );
  }

  Future<void> publishScreenshotFiles(List<File> files) async {
    final payload = <Map<String, dynamic>>[];
    for (final file in files) {
      final objectId = await _uploadFileToObs(file);
      payload.add(<String, dynamic>{'fileDestUrl': objectId});
    }
    await _publishFileInfo(fileType: 2, files: payload);
  }

  Future<void> publishApkFile(File file) async {
    final objectId = await _uploadFileToObs(file);
    await _publishFileInfo(
      fileType: 5,
      files: <Map<String, dynamic>>[
        <String, dynamic>{'fileName': _fileName(file), 'fileDestUrl': objectId},
      ],
    );
  }

  Future<void> submitApp() async {
    const submitDelay = Duration(seconds: 20);
    const retryDelay = Duration(seconds: 10);
    const maxAttempts = 4;

    await Future<void>.delayed(submitDelay);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final body = await _sendRequest(
        'POST',
        '/publish/v2/app-submit',
        queryParameters: <String, dynamic>{
          'releaseType': 1,
          'appId': credentials.appId,
        },
      );
      final ret = body['ret'];
      if (ret is! Map || ret['code'] == 0) {
        return;
      }

      final code = int.tryParse(ret['code']?.toString() ?? '');
      final message = ret['msg']?.toString() ?? 'Huawei API request failed.';
      final isCompiling =
          code == 204144727 || message.contains('being compiled');
      if (!isCompiling || attempt == maxAttempts) {
        throw StateError(message);
      }
      await Future<void>.delayed(retryDelay);
    }
  }

  Future<void> _publishFileInfo({
    required int fileType,
    required List<Map<String, dynamic>> files,
  }) async {
    await _request(
      'PUT',
      '/publish/v2/app-file-info',
      queryParameters: <String, dynamic>{'appId': credentials.appId},
      data: <String, dynamic>{'fileType': fileType, 'files': files},
    );
  }

  Future<String> _uploadFileToObs(File file) async {
    final uploadInfo = await _request(
      'GET',
      '/publish/v2/upload-url/for-obs',
      queryParameters: <String, dynamic>{
        'appId': credentials.appId,
        'fileName': _fileName(file),
        'contentLength': await file.length(),
      },
    );

    final urlInfo = uploadInfo['urlInfo'] as Map<String, dynamic>? ?? const {};
    final uploadHeaders = Map<String, dynamic>.from(
      urlInfo['headers'] as Map? ?? const <String, dynamic>{},
    );
    uploadHeaders['Content-Length'] = await file.length();

    final uploader = Dio(
      BaseOptions(
        contentType: 'application/octet-stream',
        headers: uploadHeaders,
      ),
    );
    await uploader.putUri(
      Uri.parse(urlInfo['url'] as String),
      data: file.openRead(),
    );
    return urlInfo['objectId'] as String;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? data,
  }) async {
    final body = await _sendRequest(
      method,
      path,
      queryParameters: queryParameters,
      data: data,
    );
    final ret = body['ret'];
    if (ret is Map && ret['code'] != 0) {
      throw StateError(ret['msg']?.toString() ?? 'Huawei API request failed.');
    }
    return body;
  }

  Future<Map<String, dynamic>> _sendRequest(
    String method,
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? data,
  }) async {
    await _ensureToken();
    final response = await _dio.request<Map<String, dynamic>>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: Options(
        method: method,
        headers: <String, dynamic>{
          'Authorization': 'Bearer $_accessToken',
          'client_id': credentials.clientId,
        },
      ),
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> _ensureToken() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_accessToken != null && now < _expiresAt) {
      return;
    }

    final tokenClient = Dio(
      BaseOptions(contentType: 'application/json;charset=UTF-8'),
    );
    final response = await tokenClient.post<Map<String, dynamic>>(
      'https://connect-api.cloud.huawei.com/api/oauth2/v1/token',
      data: <String, dynamic>{
        'client_id': credentials.clientId,
        'client_secret': credentials.clientSecret,
        'grant_type': 'client_credentials',
      },
    );
    final body = response.data ?? const <String, dynamic>{};
    final token = body['access_token']?.toString() ?? '';
    if (token.isEmpty) {
      throw StateError('Huawei token request failed.');
    }
    _accessToken = token;
    final expiresIn = int.tryParse(body['expires_in']?.toString() ?? '') ?? 0;
    _expiresAt =
        DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000) - 60000;
  }

  String _fileName(File file) {
    if (file.uri.pathSegments.isEmpty) {
      return file.path;
    }
    return file.uri.pathSegments.last;
  }
}
