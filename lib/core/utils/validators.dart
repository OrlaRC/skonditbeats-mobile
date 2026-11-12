/// Validaciones de formularios. Replican la política del backend
/// (api/src/plugins/password.ts) para avisar antes de enviar.
class Validators {
  Validators._();

  static const int passwordMinLength = 10;

  static final _email = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
  static final _phone = RegExp(r'^\d{10,13}$');

  /// [mensaje] es el texto completo, p. ej. 'Ingresa tu contraseña'.
  static String? required(String? v, [String mensaje = 'Este campo es obligatorio']) =>
      (v == null || v.trim().isEmpty) ? mensaje : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'El correo es obligatorio';
    if (!_email.hasMatch(v.trim())) return 'Ingresa un correo válido';
    return null;
  }

  static String? name(String? v) {
    if (v == null || v.trim().length < 2) return 'Ingresa tu nombre (mínimo 2 letras)';
    return null;
  }

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return null; // opcional
    if (!_phone.hasMatch(v.trim())) return 'Teléfono de 10 a 13 dígitos';
    return null;
  }

  static String? age(String? v) {
    final n = int.tryParse(v ?? '');
    if (n == null) return 'Ingresa tu edad';
    if (n < 18) return 'Debes ser mayor de edad';
    if (n > 120) return 'Edad no válida';
    return null;
  }

  /// Reglas de la contraseña con su estado, para mostrarlas en vivo.
  static Map<String, bool> passwordRules(String p) => {
        'Mínimo $passwordMinLength caracteres': p.length >= passwordMinLength,
        'Una letra mayúscula': RegExp(r'[A-Z]').hasMatch(p),
        'Una letra minúscula': RegExp(r'[a-z]').hasMatch(p),
        'Un número': RegExp(r'\d').hasMatch(p),
        'Un carácter especial': RegExp(r'[^A-Za-z0-9]').hasMatch(p),
      };

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'La contraseña es obligatoria';
    final failed = passwordRules(v).entries.where((e) => !e.value);
    return failed.isEmpty ? null : 'Falta: ${failed.first.key.toLowerCase()}';
  }

  static String? otp(String? v) {
    if (v == null || !RegExp(r'^\d{6}$').hasMatch(v)) return 'El código tiene 6 dígitos';
    return null;
  }

  // ── Tarjeta (pago simulado) ─────────────────────────────────────────────

  static String _digits(String? v) => (v ?? '').replaceAll(RegExp(r'\D'), '');

  /// Algoritmo de Luhn: detecta errores de captura en el número de tarjeta.
  static bool luhn(String digits) {
    var sum = 0;
    for (var i = 0; i < digits.length; i++) {
      var d = int.parse(digits[digits.length - 1 - i]);
      if (i.isOdd) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
    }
    return digits.isNotEmpty && sum % 10 == 0;
  }

  static String? cardNumber(String? v) {
    final d = _digits(v);
    if (d.length != 16) return 'La tarjeta tiene 16 dígitos';
    if (!luhn(d)) return 'Número de tarjeta no válido';
    return null;
  }

  static String? cardName(String? v) {
    if (v == null || v.trim().length < 4) return 'Escribe el nombre como aparece en la tarjeta';
    return null;
  }

  /// Formato MM/AA, mes válido y que no esté vencida.
  static String? cardExpiry(String? v, {DateTime? now}) {
    final m = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(v ?? '');
    if (m == null) return 'Usa el formato MM/AA';
    final mes = int.parse(m.group(1)!);
    final anio = 2000 + int.parse(m.group(2)!);
    if (mes < 1 || mes > 12) return 'Mes no válido';
    final hoy = now ?? DateTime.now();
    if (anio < hoy.year || (anio == hoy.year && mes < hoy.month)) return 'La tarjeta está vencida';
    return null;
  }

  static String? cvv(String? v) {
    final d = _digits(v);
    if (d.length < 3 || d.length > 4) return 'CVV de 3 o 4 dígitos';
    return null;
  }
}
