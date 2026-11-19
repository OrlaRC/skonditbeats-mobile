// Prácticas 13 y 14 · AUT-01 (unitarias) · Función crítica: registro e inicio de sesión.
// Valida las reglas que la app aplica ANTES de mandar el formulario a la API
// (deben coincidir con api/src/plugins/password.ts y el esquema de /auth/register).
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/utils/validators.dart';
import 'package:skondit_beats_mobile/features/auth/data/auth_repository.dart';

void main() {
  group('AUT-01 · Correo', () {
    test('entrada válida → sin error (también con espacios alrededor)', () {
      expect(Validators.email('cliente@skondit.com'), isNull);
      expect(Validators.email('  orlando.rc+beats@mail.com.mx '), isNull);
    });

    test('entrada vacía o nula → "El correo es obligatorio"', () {
      for (final v in [null, '', '   ']) {
        expect(Validators.email(v), 'El correo es obligatorio', reason: 'valor: "$v"');
      }
    });

    test('formatos inválidos → "Ingresa un correo válido"', () {
      for (final v in ['cliente', 'cliente@', '@skondit.com', 'cliente@skondit', 'a b@c.com', 'a@@b.com']) {
        expect(Validators.email(v), 'Ingresa un correo válido', reason: v);
      }
    });
  });

  group('AUT-01 · Contraseña (misma política que el backend)', () {
    test('entrada válida → sin error', () {
      expect(Validators.password('Skondit2026!'), isNull);
    });

    test('vacía o nula → obligatoria', () {
      expect(Validators.password(null), 'La contraseña es obligatoria');
      expect(Validators.password(''), 'La contraseña es obligatoria');
    });

    test('límite de longitud: 9 caracteres no, 10 sí', () {
      expect(Validators.password('Abcdef12!'), 'Falta: mínimo 10 caracteres');
      expect(Validators.password('Abcdefg12!'), isNull);
    });

    test('resultado esperado: dice exactamente la primera regla que falta', () {
      expect(Validators.password('abcdefghij1!'), 'Falta: una letra mayúscula');
      expect(Validators.password('ABCDEFGHIJ1!'), 'Falta: una letra minúscula');
      expect(Validators.password('Abcdefghij!'), 'Falta: un número');
      expect(Validators.password('Abcdefghij1'), 'Falta: un carácter especial');
      final reglas = Validators.passwordRules('abc');
      expect(reglas.values.where((ok) => ok), hasLength(1)); // solo "minúscula"
    });
  });

  group('AUT-01 · Edad, teléfono, nombre y código OTP', () {
    test('edad: valores en rango y en los límites', () {
      expect(Validators.age('18'), isNull);
      expect(Validators.age('120'), isNull);
    });

    test('edad: fuera de rango', () {
      expect(Validators.age('17'), 'Debes ser mayor de edad');
      expect(Validators.age('-5'), 'Debes ser mayor de edad');
      expect(Validators.age('121'), 'Edad no válida');
    });

    test('edad: vacía, nula, con decimales o texto → se pide de nuevo', () {
      for (final v in [null, '', 'veinte', '18.5', '99999999999999999999999']) {
        expect(Validators.age(v), 'Ingresa tu edad', reason: 'valor: "$v"');
      }
    });

    test('teléfono: opcional, pero si se escribe debe tener 10 a 13 dígitos', () {
      expect(Validators.phone(null), isNull);
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('4421234567'), isNull);
      expect(Validators.phone('524421234567'), isNull);
      expect(Validators.phone('442123456'), 'Teléfono de 10 a 13 dígitos'); // 9
      expect(Validators.phone('44212345678901'), 'Teléfono de 10 a 13 dígitos'); // 14
      expect(Validators.phone('442-123-4567'), 'Teléfono de 10 a 13 dígitos');
    });

    test('nombre: mínimo 2 letras sin contar espacios', () {
      expect(Validators.name('Al'), isNull);
      expect(Validators.name(' A '), isNotNull);
      expect(Validators.name(null), isNotNull);
    });

    test('OTP: exactamente 6 dígitos', () {
      expect(Validators.otp('123456'), isNull);
      for (final v in [null, '', '12345', '1234567', '12a456', ' 123456']) {
        expect(Validators.otp(v), 'El código tiene 6 dígitos', reason: 'valor: "$v"');
      }
    });
  });

  group('AUT-01 · Datos que se envían al registrarse', () {
    test('normaliza correo y nombre y omite los opcionales vacíos', () {
      const datos = RegisterData(
        nombre: '  Orlando  ',
        email: '  Orlando@Mail.COM ',
        password: 'Skondit2026!',
        edad: 21,
        username: '   ',
        telefono: '',
      );
      expect(datos.toJson(), {
        'nombre': 'Orlando',
        'email': 'orlando@mail.com',
        'password': 'Skondit2026!',
        'edad': 21,
      });
    });

    test('incluye usuario y teléfono cuando sí se capturan', () {
      const datos = RegisterData(
        nombre: 'Ana',
        email: 'ana@mail.com',
        password: 'Skondit2026!',
        edad: 30,
        username: ' ana_beats ',
        telefono: ' 4421234567 ',
      );
      expect(datos.toJson()['username'], 'ana_beats');
      expect(datos.toJson()['telefono'], '4421234567');
    });
  });
}
