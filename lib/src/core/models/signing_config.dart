class SigningConfig {
  const SigningConfig({
    this.keystorePath = '',
    this.storePassword = '',
    this.keyAlias = '',
    this.keyPassword = '',
  });

  final String keystorePath;
  final String storePassword;
  final String keyAlias;
  final String keyPassword;

  bool get isEmpty =>
      keystorePath.isEmpty &&
      storePassword.isEmpty &&
      keyAlias.isEmpty &&
      keyPassword.isEmpty;

  SigningConfig copyWith({
    String? keystorePath,
    String? storePassword,
    String? keyAlias,
    String? keyPassword,
  }) {
    return SigningConfig(
      keystorePath: keystorePath ?? this.keystorePath,
      storePassword: storePassword ?? this.storePassword,
      keyAlias: keyAlias ?? this.keyAlias,
      keyPassword: keyPassword ?? this.keyPassword,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'keystorePath': keystorePath,
      'storePassword': storePassword,
      'keyAlias': keyAlias,
      'keyPassword': keyPassword,
    };
  }

  Map<String, dynamic> toConfigJson() {
    final json = <String, dynamic>{};
    if (keystorePath.trim().isNotEmpty) {
      json['keystorePath'] = keystorePath;
    }
    if (storePassword.isNotEmpty) {
      json['storePassword'] = storePassword;
    }
    if (keyAlias.trim().isNotEmpty) {
      json['keyAlias'] = keyAlias;
    }
    if (keyPassword.isNotEmpty) {
      json['keyPassword'] = keyPassword;
    }
    return json;
  }

  factory SigningConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SigningConfig();
    }
    return SigningConfig(
      keystorePath: json['keystorePath'] as String? ?? '',
      storePassword: json['storePassword'] as String? ?? '',
      keyAlias: json['keyAlias'] as String? ?? '',
      keyPassword: json['keyPassword'] as String? ?? '',
    );
  }
}
