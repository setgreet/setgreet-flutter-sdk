import 'package:flutter/material.dart';
import 'package:setgreet/setgreet.dart';
import 'config.dart';

void main() {
  runApp(const SetgreetExampleApp());
}

class SetgreetExampleApp extends StatelessWidget {
  const SetgreetExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Setgreet Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _appKeyController = TextEditingController();
  final TextEditingController _flowIdController = TextEditingController();
  final List<String> _eventLogs = [];

  @override
  void initState() {
    super.initState();
    _appKeyController.text = exampleConfig.appKey;
    _flowIdController.text = exampleConfig.testFlowId;
    _setupFlowCallbacks();
  }

  void _setupFlowCallbacks() {
    Setgreet.setFlowCallbacks(
      SetgreetFlowCallbacks()
        ..onFlowStarted((event) {
          _addLog('Flow Started: ${event.flowId} (${event.screenCount} screens)');
        })
        ..onFlowCompleted((event) {
          _addLog('Flow Completed: ${event.flowId} in ${event.durationMs}ms');
        })
        ..onFlowDismissed((event) {
          _addLog(
              'Flow Dismissed: ${event.reason.name} at screen ${event.screenIndex + 1}/${event.screenCount}');
        })
        ..onScreenChanged((event) {
          _addLog('Screen Changed: ${event.fromIndex + 1} -> ${event.toIndex + 1}');
        })
        ..onActionTriggered((event) {
          var log = 'Action: ${event.actionType}';
          if (event.actionName != null) {
            log += ' (event: ${event.actionName})';
          }
          _addLog(log);
        })
        ..onPermissionRequested((event) {
          _addLog('Permission: ${event.permissionType.name} -> ${event.result.name}');
        })
        ..onError((event) {
          _addLog('Error: ${event.errorType.name} - ${event.message}');
        }),
    );
  }

  void _addLog(String message) {
    final timestamp = TimeOfDay.now().format(context);
    setState(() {
      _eventLogs.insert(0, '[$timestamp] $message');
    });
  }

  void _clearLogs() {
    setState(() {
      _eventLogs.clear();
    });
  }

  Future<void> _handleInitialize() async {
    try {
      final appKey = _appKeyController.text.trim();
      if (appKey.isEmpty) {
        _showMessage('Please enter a valid app key', Colors.orange);
        return;
      }

      await Setgreet.initialize(
        appKey,
        config: SetgreetConfig(debugMode: exampleConfig.debugMode),
      );

      await Setgreet.identifyUser(
        exampleConfig.testUserId,
        attributes: exampleConfig.testUserAttributes,
        operation: 'create',
        locale: 'en-US',
      );

      _showMessage('SDK initialized successfully!', Colors.green);
    } catch (e) {
      _showMessage('Failed to initialize: $e', Colors.red);
    }
  }

  Future<void> _handleShowFlow() async {
    try {
      final flowId = _flowIdController.text.trim();
      if (flowId.isEmpty) {
        _showMessage('Please enter a valid flow ID', Colors.orange);
        return;
      }

      await Setgreet.showFlow(flowId);
    } catch (e) {
      _showMessage('Failed to show flow: $e', Colors.red);
    }
  }

  Future<void> _handleTrackEvent() async {
    try {
      await Setgreet.trackEvent('button_clicked', properties: {
        'button': 'track_event',
        'timestamp': DateTime.now().toIso8601String(),
      });
      _showMessage('Event tracked successfully!', Colors.green);
    } catch (e) {
      _showMessage('Failed to track event: $e', Colors.red);
    }
  }

  void _showMessage(String message, Color backgroundColor) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setgreet Flutter SDK'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Setgreet SDK Example',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // App Key Input
              _buildInputSection(
                'App Key',
                _appKeyController,
                'Enter your Setgreet app key',
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _handleInitialize,
                child: const Text('Initialize SDK'),
              ),

              const SizedBox(height: 32),

              // Flow ID Input
              _buildInputSection(
                'Flow ID',
                _flowIdController,
                'Enter flow ID to display',
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _handleShowFlow,
                child: const Text('Show Flow'),
              ),

              const SizedBox(height: 32),

              // Additional Actions
              const Text(
                'Additional Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _handleTrackEvent,
                      child: const Text('Track Event'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await Setgreet.trackScreen('example_screen', properties: {
                            'action': 'screen_view',
                          });
                          _showMessage('Screen tracked!', Colors.green);
                        } catch (e) {
                          _showMessage('Failed to track screen: $e', Colors.red);
                        }
                      },
                      child: const Text('Track Screen'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: () async {
                  try {
                    await Setgreet.resetUser();
                    _showMessage('User reset successfully!', Colors.green);
                  } catch (e) {
                    _showMessage('Failed to reset user: $e', Colors.red);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Reset User'),
              ),

              // Event Logs Section
              if (_eventLogs.isNotEmpty) ...[
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Event Logs',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: _clearLogs,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 150,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: _eventLogs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          _eventLogs[index],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputSection(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _appKeyController.dispose();
    _flowIdController.dispose();
    Setgreet.clearFlowCallbacks();
    super.dispose();
  }
}
