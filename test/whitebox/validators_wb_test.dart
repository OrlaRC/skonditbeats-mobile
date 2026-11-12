// Práctica 11 · Caja blanca del MÉTODO DE VALIDACIÓN: Validators.cardExpiry
// y del MÉTODO DE CÁLCULO: Validators.luhn. Cada prueba indica el camino del grafo
// de flujo que recorre (docs/practica11/README.md, sección M1 y M2).
//   flutter test --coverage --branch-coverage test/whitebox
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/utils/validators.dart';

void main() {
  // Fecha fija: las pruebas no dependen del día en que se ejecutan.
  final hoy = DateTime(2026, 11, 11);
  String? exp(String? v) => Validators.cardExpiry(v, now: hoy);

  group('M1 · cardExpiry — caminos independientes', () {
    test('P1 formato inválido → "Usa el formato MM/AA"', () {
      expect(exp('1126'), 'Usa el formato MM/AA');
    });
    test('P2 mes fuera de rango por abajo (mes < 1)', () {
      expect(exp('00/27'), 'Mes no válido');
    });
    test('P3 mes fuera de rango por arriba (mes > 12)', () {
      expect(exp('13/27'), 'Mes no válido');
    });
    test('P4 año anterior al actual → vencida', () {
      expect(exp('12/25'), 'La tarjeta está vencida');
    });
    test('P5 mismo año, mes anterior → vencida', () {
      expect(exp('10/26'), 'La tarjeta está vencida');
    });
    test('P6 mismo año, mes actual → válida', () {
      expect(exp('11/26'), isNull);
    });
    test('P7 año futuro → válida', () {
      expect(exp('01/27'), isNull);
    });
    test('P8 vencimiento absurdo (más de 20 años) → rechazada', () {
      // DEF-06: antes "12/99" (año 2099) se aceptaba como vigente.
      expect(exp('12/99'), 'Fecha no válida');
      expect(exp('12/46'), isNull, reason: 'el límite de 20 años sí es válido');
      expect(exp('01/47'), 'Fecha no válida', reason: 'límite + 1');
    });
    test('sin fecha inyectada usa el reloj del sistema (rama del operador ??)', () {
      expect(Validators.cardExpiry('01/99'), isNotNull);
    });
  });

  group('M1 · cardExpiry — cobertura de condiciones (MC/DC)', () {
    // Decisión D2: mes < 1 || mes > 12
    test('D2 · (F,F) mes 01 y (F,F) mes 12 → pasa', () {
      expect(exp('01/27'), isNull);
      expect(exp('12/26'), isNull);
    });
    test('D2 · (V,–) mes 00 y (F,V) mes 13 → falla', () {
      expect(exp('00/27'), 'Mes no válido');
      expect(exp('13/27'), 'Mes no válido');
    });
    // Decisión D3: anio < hoy.year || (anio == hoy.year && mes < hoy.month)
    test('D3 · A=V → vencida', () => expect(exp('12/25'), isNotNull));
    test('D3 · A=F, B=F (año futuro) → vigente', () => expect(exp('01/27'), isNull));
    test('D3 · A=F, B=V, C=V → vencida', () => expect(exp('10/26'), isNotNull));
    test('D3 · A=F, B=V, C=F → vigente', () => expect(exp('12/26'), isNull));
  });

  group('M1 · cardExpiry — valores límite y entradas raras', () {
    test('null y vacío', () {
      expect(exp(null), 'Usa el formato MM/AA');
      expect(exp(''), 'Usa el formato MM/AA');
    });
    test('un dígito de más o de menos', () {
      expect(exp('1/27'), 'Usa el formato MM/AA');
      expect(exp('011/27'), 'Usa el formato MM/AA');
      expect(exp('01/2027'), 'Usa el formato MM/AA');
    });
    test('espacios alrededor no se aceptan', () => expect(exp(' 01/27'), 'Usa el formato MM/AA'));
    test('cambio de año: diciembre del año pasado vs enero del siguiente', () {
      final enero = DateTime(2027, 1, 1);
      expect(Validators.cardExpiry('12/26', now: enero), 'La tarjeta está vencida');
      expect(Validators.cardExpiry('01/27', now: enero), isNull);
    });
  });

  group('M2 · luhn — caminos del ciclo', () {
    test('P1 cadena vacía: el ciclo no se ejecuta → false', () {
      expect(Validators.luhn(''), isFalse);
    });
    test('P2 un dígito: una vuelta, sin duplicar (i par)', () {
      expect(Validators.luhn('0'), isTrue);
      expect(Validators.luhn('5'), isFalse);
    });
    test('P3 dígito duplicado ≤ 9 (no resta 9)', () {
      // "18": 8 + (1·2 = 2) = 10 → válido
      expect(Validators.luhn('18'), isTrue);
    });
    test('P4 dígito duplicado > 9 (resta 9)', () {
      // "59": 9 + (5·2 = 10 → 1) = 10 → válido
      expect(Validators.luhn('59'), isTrue);
    });
    test('P5 tarjetas de prueba reales de 16 dígitos', () {
      expect(Validators.luhn('4242424242424242'), isTrue);
      expect(Validators.luhn('5555555555554444'), isTrue);
      expect(Validators.luhn('4242424242424241'), isFalse);
    });
  });

  group('M2 · luhn — pruebas de excepciones', () {
    test('caracteres que no son dígitos no lanzan FormatException', () {
      // DEF-07: luhn() es público y hacía int.parse() de cada carácter;
      // con "4242-4242" lanzaba FormatException en lugar de responder false.
      expect(() => Validators.luhn('4242-4242'), returnsNormally);
      expect(Validators.luhn('4242-4242'), isFalse);
      expect(Validators.luhn('abc'), isFalse);
    });
    test('cardNumber limpia separadores antes de llamar a luhn', () {
      expect(Validators.cardNumber('4242 4242 4242 4242'), isNull);
      expect(Validators.cardNumber('4242-4242-4242-4242'), isNull);
    });
    test('cardNumber: 15 y 17 dígitos (valores límite de longitud)', () {
      expect(Validators.cardNumber('424242424242424'), 'La tarjeta tiene 16 dígitos');
      expect(Validators.cardNumber('42424242424242424'), 'La tarjeta tiene 16 dígitos');
      expect(Validators.cardNumber(null), 'La tarjeta tiene 16 dígitos');
    });
  });

  group('Valores límite de otras validaciones', () {
    test('edad 17 / 18 / 120 / 121', () {
      expect(Validators.age('17'), 'Debes ser mayor de edad');
      expect(Validators.age('18'), isNull);
      expect(Validators.age('120'), isNull);
      expect(Validators.age('121'), 'Edad no válida');
      expect(Validators.age('18.5'), 'Ingresa tu edad');
      expect(Validators.age(null), 'Ingresa tu edad');
    });
    test('contraseña de 9 y 10 caracteres', () {
      expect(Validators.password('Abcdef1!x'), contains('mínimo 10'));
      expect(Validators.password('Abcdef1!xy'), isNull);
      expect(Validators.password(''), 'La contraseña es obligatoria');
    });
    test('cada regla de la contraseña falla por separado', () {
      expect(Validators.password('abcdefgh1!'), contains('mayúscula'));
      expect(Validators.password('ABCDEFGH1!'), contains('minúscula'));
      expect(Validators.password('Abcdefghi!'), contains('número'));
      expect(Validators.password('Abcdefghi1'), contains('especial'));
    });
    test('teléfono de 9 / 10 / 13 / 14 dígitos y opcional', () {
      expect(Validators.phone('123456789'), isNotNull);
      expect(Validators.phone('1234567890'), isNull);
      expect(Validators.phone('1234567890123'), isNull);
      expect(Validators.phone('12345678901234'), isNotNull);
      expect(Validators.phone(''), isNull);
    });
    test('CVV de 2 / 3 / 4 / 5 dígitos', () {
      expect(Validators.cvv('12'), isNotNull);
      expect(Validators.cvv('123'), isNull);
      expect(Validators.cvv('1234'), isNull);
      expect(Validators.cvv('12345'), isNotNull);
    });
    test('OTP de 5 / 6 / 7 dígitos y con letras', () {
      expect(Validators.otp('12345'), isNotNull);
      expect(Validators.otp('123456'), isNull);
      expect(Validators.otp('1234567'), isNotNull);
      expect(Validators.otp('12345a'), isNotNull);
    });
    test('correo', () {
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('a@b'), 'Ingresa un correo válido');
      expect(Validators.email('  '), 'El correo es obligatorio');
    });
    test('nombres y titular', () {
      expect(Validators.name('A'), isNotNull);
      expect(Validators.name('Al'), isNull);
      expect(Validators.cardName('Ana'), isNotNull);
      expect(Validators.cardName('Ana R'), isNull);
      expect(Validators.required(' '), 'Este campo es obligatorio');
      expect(Validators.required('x'), isNull);
    });
  });
}
