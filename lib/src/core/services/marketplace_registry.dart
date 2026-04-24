import '../models/market_type.dart';
import 'markets/huawei_marketplace_uploader.dart';
import 'markets/oppo_marketplace_uploader.dart';
import 'markets/vivo_marketplace_uploader.dart';
import 'markets/xiaomi_marketplace_uploader.dart';
import 'markets/yingyongbao_marketplace_uploader.dart';
import 'marketplace_uploader.dart';

class MarketplaceRegistry {
  MarketplaceRegistry(Map<MarketType, MarketplaceUploader> uploaders)
    : _uploaders = uploaders;

  final Map<MarketType, MarketplaceUploader> _uploaders;

  factory MarketplaceRegistry.defaultRegistry() {
    return MarketplaceRegistry({
      MarketType.huawei: HuaweiMarketplaceUploader(),
      MarketType.xiaomi: XiaomiMarketplaceUploader(),
      MarketType.oppo: OppoMarketplaceUploader(),
      MarketType.vivo: VivoMarketplaceUploader(),
      MarketType.tencent: YingyongbaoMarketplaceUploader(),
    });
  }

  MarketplaceUploader? operator [](MarketType market) => _uploaders[market];
}
