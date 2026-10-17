class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    const configured = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8787',
    );
    return AppConfig(apiBaseUrl: configured.replaceFirst(RegExp(r'/$'), ''));
  }

  final String apiBaseUrl;
}
