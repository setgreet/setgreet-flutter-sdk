/// Base exception class for Setgreet SDK errors
class SetgreetException implements Exception {
  /// Error message
  final String message;

  /// Error code if available
  final String? code;

  /// Creates a new SetgreetException
  SetgreetException(this.message, {this.code});

  @override
  String toString() => 'SetgreetException${code != null ? '[$code]' : ''}: $message';
}

/// Exception thrown when SDK initialization fails
class SetgreetInitializationException extends SetgreetException {
  /// Creates a new SetgreetInitializationException
  SetgreetInitializationException(String message, {String? code})
      : super(message, code: code);
}

/// Exception thrown when user identification fails
class SetgreetUserException extends SetgreetException {
  /// Creates a new SetgreetUserException
  SetgreetUserException(String message, {String? code})
      : super(message, code: code);
}

/// Exception thrown when event tracking fails
class SetgreetTrackingException extends SetgreetException {
  /// Creates a new SetgreetTrackingException
  SetgreetTrackingException(String message, {String? code})
      : super(message, code: code);
}

/// Exception thrown when flow operations fail
class SetgreetFlowException extends SetgreetException {
  /// Creates a new SetgreetFlowException
  SetgreetFlowException(String message, {String? code})
      : super(message, code: code);
}
