import '../models/market_type.dart';
import 'generic_marketplace_uploader.dart';
import 'marketplace_uploader.dart';

class MarketplaceRegistry {
  MarketplaceRegistry(Map<MarketType, MarketplaceUploader> uploaders)
    : _uploaders = uploaders;

  final Map<MarketType, MarketplaceUploader> _uploaders;

  factory MarketplaceRegistry.defaultRegistry() {
    return MarketplaceRegistry({
      for (final market in MarketType.values)
        market: GenericMarketplaceUploader(market),
    });
  }

  MarketplaceUploader? operator [](MarketType market) => _uploaders[market];
}
