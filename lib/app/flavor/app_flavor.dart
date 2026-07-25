enum AppFlavor {
  dev,
  staging,
  prod;

  static AppFlavor fromDartDefine() {
    const value = String.fromEnvironment('APP_FLAVOR', defaultValue: 'dev');
    return fromName(value);
  }

  static AppFlavor fromName(String value) {
    return switch (value.trim().toLowerCase()) {
      'dev' || 'development' => AppFlavor.dev,
      'staging' || 'stage' => AppFlavor.staging,
      'prod' || 'production' => AppFlavor.prod,
      _ => AppFlavor.dev,
    };
  }

  String get label {
    return switch (this) {
      AppFlavor.dev => 'Dev',
      AppFlavor.staging => 'Staging',
      AppFlavor.prod => 'Production',
    };
  }

  Uri get defaultApiBaseUri {
    return switch (this) {
      AppFlavor.dev => Uri.parse('https://chat.vpsttt.com'),
      AppFlavor.staging => Uri.parse('https://chat.vpsttt.com'),
      AppFlavor.prod => Uri.parse('https://chat.vpsttt.com'),
    };
  }
}
