/// Configuración por ambiente. Se inyecta en compilación con --dart-define,
/// así no queda ninguna URL ni secreto escrito en el código.
///
///   flutter run --dart-define=API_URL=http://10.0.2.2:3000/api
class Env {
  Env._();

  /// URL base de la API de SkonditBeats (la misma que usa la web).
  /// Por defecto apunta al host de la PC desde el emulador de Android.
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000/api',
  );

  /// Con hasta 2 reintentos automáticos, un servidor que no responde se
  /// reporta al usuario en unos 25 s como máximo.
  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
