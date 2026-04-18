enum MarketType {
  huawei('huawei', '华为应用市场'),
  xiaomi('xiaomi', '小米应用商店'),
  oppo('oppo', 'OPPO 软件商店'),
  vivo('vivo', 'vivo 应用商店'),
  yingyongbao('yingyongbao', '应用宝');

  const MarketType(this.id, this.displayName);

  final String id;
  final String displayName;

  static MarketType? tryParse(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final value in values) {
      if (value.id == normalized) {
        return value;
      }
    }
    return null;
  }
}
