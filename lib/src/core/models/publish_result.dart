import 'market_type.dart';

class PublishResult {
  const PublishResult({
    required this.projectId,
    required this.apkPath,
    required this.results,
  });

  final String projectId;
  final String apkPath;
  final List<MarketPublishResult> results;

  bool get isSuccess => results.every((result) => result.success);
}

class MarketPublishResult {
  const MarketPublishResult({
    required this.market,
    required this.success,
    required this.message,
    this.statusCode,
    this.duration,
  });

  final MarketType market;
  final bool success;
  final String message;
  final int? statusCode;
  final Duration? duration;
}
