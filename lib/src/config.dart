/// Configuration class for Setgreet SDK initialization
class SetgreetConfig {
  /// Whether to enable debug mode for development
  final bool debugMode;

  /// Creates a new SetgreetConfig instance
  const SetgreetConfig({
    this.debugMode = false,
  });

  /// Converts the config to a map for platform channel communication
  Map<String, dynamic> toMap() {
    return {
      'debugMode': debugMode,
    };
  }
}
