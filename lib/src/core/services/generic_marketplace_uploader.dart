import 'dart:convert';
import 'dart:io';

import '../models/market_channel_config.dart';
import '../models/market_type.dart';
import '../models/project_config.dart';
import '../models/publish_request.dart';
import '../models/publish_result.dart';
import 'marketplace_uploader.dart';

class GenericMarketplaceUploader extends MarketplaceUploader {
  const GenericMarketplaceUploader(this.market);

  final MarketType market;

  @override
  Future<MarketPublishResult> upload({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required File apkFile,
    required PublishRequest request,
  }) async {
    final startedAt = DateTime.now();
    final effectiveNotes = request.releaseNotesOverride ?? channel.releaseNotes;

    if (request.dryRun || channel.endpoint.trim().isEmpty) {
      return MarketPublishResult(
        market: market,
        success: true,
        message: request.dryRun
            ? 'Dry run completed for ${market.displayName}.'
            : 'No endpoint configured, upload simulated for ${market.displayName}.',
        duration: DateTime.now().difference(startedAt),
      );
    }

    try {
      final response = await _sendMultipartRequest(
        uri: Uri.parse(channel.endpoint),
        apkFile: apkFile,
        token: channel.authToken,
        track: channel.track,
        releaseNotes: effectiveNotes,
        headers: channel.headers,
        fields: {
          'project_name': project.name,
          'output_directory': project.outputDirectory,
          'market': channel.market.id,
          ...channel.fields,
        },
      );

      final responseBody = await response.transform(utf8.decoder).join();
      final success = response.statusCode >= 200 && response.statusCode < 300;
      final message = responseBody.trim().isEmpty
          ? 'HTTP ${response.statusCode}'
          : responseBody.trim();

      return MarketPublishResult(
        market: market,
        success: success,
        message: message,
        statusCode: response.statusCode,
        duration: DateTime.now().difference(startedAt),
      );
    } on FormatException catch (error) {
      return MarketPublishResult(
        market: market,
        success: false,
        message: 'Invalid endpoint: ${error.message}',
        duration: DateTime.now().difference(startedAt),
      );
    } on SocketException catch (error) {
      return MarketPublishResult(
        market: market,
        success: false,
        message: 'Network error: ${error.message}',
        duration: DateTime.now().difference(startedAt),
      );
    } catch (error) {
      return MarketPublishResult(
        market: market,
        success: false,
        message: error.toString(),
        duration: DateTime.now().difference(startedAt),
      );
    }
  }

  Future<HttpClientResponse> _sendMultipartRequest({
    required Uri uri,
    required File apkFile,
    required String token,
    required String track,
    required String releaseNotes,
    required Map<String, String> headers,
    required Map<String, String> fields,
  }) async {
    final client = HttpClient();
    final boundary = '----apk-publish-${DateTime.now().microsecondsSinceEpoch}';
    final request = await client.postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );

    if (token.trim().isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${token.trim()}',
      );
    }

    headers.forEach(request.headers.set);

    void writeField(String name, String value) {
      request.write('--$boundary\r\n');
      request.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
      request.write(value);
      request.write('\r\n');
    }

    for (final entry in fields.entries) {
      writeField(entry.key, entry.value);
    }
    writeField('track', track);
    if (releaseNotes.trim().isNotEmpty) {
      writeField('release_notes', releaseNotes.trim());
    }

    request.write('--$boundary\r\n');
    request.write(
      'Content-Disposition: form-data; name="file"; filename="${apkFile.uri.pathSegments.isEmpty ? apkFile.path : apkFile.uri.pathSegments.last}"\r\n',
    );
    request.write(
      'Content-Type: application/vnd.android.package-archive\r\n\r\n',
    );
    await request.addStream(apkFile.openRead());
    request.write('\r\n--$boundary--\r\n');

    final response = await request.close();
    return response;
  }
}
