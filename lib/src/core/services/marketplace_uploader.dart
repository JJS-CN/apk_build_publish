import 'dart:io';

import '../models/market_channel_config.dart';
import '../models/project_config.dart';
import '../models/publish_request.dart';
import '../models/publish_result.dart';

abstract class MarketplaceUploader {
  const MarketplaceUploader();

  Future<MarketPublishResult> upload({
    required ProjectConfig project,
    required MarketChannelConfig channel,
    required File apkFile,
    required PublishRequest request,
  });
}
