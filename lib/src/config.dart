/// Configuration class for Setgreet SDK initialization
class SetgreetConfig {
  /// Whether to enable debug mode for development
  final bool debugMode;

  /// Optional override for the Setgreet API base URL (e.g. a local/staging
  /// backend). Used by the Dart-side theme sync; defaults to production.
  /// Only the host/path before `/sdk/...`, e.g. `https://api.setgreet.com/api/v1`.
  final String? apiUrl;

  /// Creates a new SetgreetConfig instance
  const SetgreetConfig({
    this.debugMode = false,
    this.apiUrl,
  });

  /// Converts the config to a map for platform channel communication
  Map<String, dynamic> toMap() {
    return {
      'debugMode': debugMode,
    };
  }
}
