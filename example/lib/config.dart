// Setgreet SDK Configuration
// Replace these values with your actual Setgreet credentials

const exampleConfig = ExampleConfig(
  // Your Setgreet app key from the dashboard
  appKey: 'YOUR_APP_KEY_HERE',

  // Test flow ID - replace with a valid flow ID from your dashboard
  testFlowId: 'YOUR_FLOW_ID_HERE',

  // Debug mode for development
  debugMode: true,

  // Test user ID
  testUserId: 'user123',

  // Test user attributes
  testUserAttributes: {
    'plan': 'pro',
    'locale': 'en-US',
    'environment': 'development',
  },
);

/// Configuration class for the example app
class ExampleConfig {
  final String appKey;
  final String testFlowId;
  final bool debugMode;
  final String testUserId;
  final Map<String, dynamic> testUserAttributes;

  const ExampleConfig({
    required this.appKey,
    required this.testFlowId,
    required this.debugMode,
    required this.testUserId,
    required this.testUserAttributes,
  });

  /// Validates the configuration
  bool validate() {
    if (appKey == 'YOUR_APP_KEY_HERE') {
      throw Exception(
        'Please replace YOUR_APP_KEY_HERE with your actual Setgreet app key in lib/config.dart'
      );
    }

    if (testFlowId == 'YOUR_FLOW_ID_HERE') {
      throw Exception(
        'Please replace YOUR_FLOW_ID_HERE with your actual Setgreet flow id in lib/config.dart'
      );
    }

    return true;
  }
}
