/// Entidad: un acceso a la cuenta registrado en este dispositivo.
class Acceso {
  const Acceso({this.id, required this.email, required this.metodo, required this.fecha});

  final int? id;
  final String email;
  final String metodo;
  final DateTime fecha;

  factory Acceso.fromMap(Map<String, Object?> m) => Acceso(
        id: m['id'] as int?,
        email: m['email'] as String,
        metodo: m['metodo'] as String,
        fecha: DateTime.parse(m['fecha'] as String),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'email': email,
        'metodo': metodo,
        'fecha': fecha.toIso8601String(),
      };
}

/// Métodos de acceso que se registran.
class MetodoAcceso {
  MetodoAcceso._();

  static const password = 'Contraseña';
  static const passwordOtp = 'Contraseña + código OTP';
  static const registro = 'Registro de cuenta';
  static const biometria = 'Desbloqueo biométrico';
}
