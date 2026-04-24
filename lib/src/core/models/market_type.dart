enum MarketType {
  huawei('huawei', '华为'),
  honor('honor', '荣耀'),
  xiaomi('xiaomi', '小米'),
  oppo('oppo', 'OPPO'),
  vivo('vivo', 'vivo'),
  tencent('tencent', '应用宝');

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
