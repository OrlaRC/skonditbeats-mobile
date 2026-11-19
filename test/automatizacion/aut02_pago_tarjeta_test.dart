// Prácticas 13 y 14 · AUT-02 (unitarias) · Función crítica: pago con tarjeta (compra).
// Incluye las regresiones de los defectos de la Práctica 11:
//   DEF-06 · "12/99" (año 2099) se aceptaba como tarjeta vigente.
//   DEF-07 · luhn() lanzaba FormatException con caracteres que no son dígitos.
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/utils/card_formatters.dart';
import 'package:skondit_beats_mobile/core/utils/validators.dart';

void main() {
  // Fecha fija: la prueba da lo mismo hoy, en un año o en el servidor de CI.
  final hoy = DateTime(2026, 11, 18);

  group('AUT-02 · Número de tarjeta (Luhn)', () {
    test('entrada válida: tarjetas de prueba Visa y Mastercard, con o sin espacios', () {
      expect(Validators.cardNumber('4242424242424242'), isNull);
      expect(Validators.cardNumber('4242 4242 4242 4242'), isNull);
      expect(Validators.cardNumber('5555555555554444'), isNull);
    });

    test('vacía o nula → pide los 16 dígitos', () {
      expect(Validators.cardNumber(null), 'La tarjeta tiene 16 dígitos');
      expect(Validators.cardNumber(''), 'La tarjeta tiene 16 dígitos');
    });

    test('longitud fuera de rango (15 y 17 dígitos)', () {
      expect(Validators.cardNumber('424242424242424'), 'La tarjeta tiene 16 dígitos');
      expect(Validators.cardNumber('42424242424242424'), 'La tarjeta tiene 16 dígitos');
    });

    test('16 dígitos con un error de captura → "no válido"', () {
      expect(Validators.cardNumber('4242424242424241'), 'Número de tarjeta no válido');
    });

    test('DEF-07 · manejo de excepciones: luhn() con letras responde false, no lanza', () {
      expect(() => Validators.luhn('4242abcd42424242'), returnsNormally);
      expect(Validators.luhn('4242abcd42424242'), isFalse);
      expect(Validators.luhn(''), isFalse);
      expect(Validators.luhn('４２４２'), isFalse); // dígitos de ancho completo
    });
  });

  group('AUT-02 · Vencimiento MM/AA', () {
    test('entrada válida: el mes actual todavía es vigente', () {
      expect(Validators.cardExpiry('11/26', now: hoy), isNull);
      expect(Validators.cardExpiry('01/30', now: hoy), isNull);
    });

    test('vacía, nula o con otro formato', () {
      for (final v in [null, '', '1126', '1/26', '11-26', '11/2026']) {
        expect(Validators.cardExpiry(v, now: hoy), 'Usa el formato MM/AA', reason: 'valor: "$v"');
      }
    });

    test('mes fuera de rango (00 y 13)', () {
      expect(Validators.cardExpiry('00/27', now: hoy), 'Mes no válido');
      expect(Validators.cardExpiry('13/27', now: hoy), 'Mes no válido');
    });

    test('tarjeta vencida (el mes anterior)', () {
      expect(Validators.cardExpiry('10/26', now: hoy), 'La tarjeta está vencida');
      expect(Validators.cardExpiry('12/25', now: hoy), 'La tarjeta está vencida');
    });

    test('DEF-06 · a más de 20 años es un error de captura', () {
      expect(Validators.cardExpiry('12/46', now: hoy), isNull); // justo 20 años
      expect(Validators.cardExpiry('01/47', now: hoy), 'Fecha no válida');
      expect(Validators.cardExpiry('12/99', now: hoy), 'Fecha no válida');
    });
  });

  group('AUT-02 · CVV, titular y formato del campo', () {
    test('CVV de 3 o 4 dígitos', () {
      expect(Validators.cvv('123'), isNull);
      expect(Validators.cvv('1234'), isNull);
      for (final v in [null, '', '12', '12345']) {
        expect(Validators.cvv(v), 'CVV de 3 o 4 dígitos', reason: 'valor: "$v"');
      }
    });

    test('titular: mínimo 4 caracteres', () {
      expect(Validators.cardName('Ana López'), isNull);
      expect(Validators.cardName('Ana'), isNotNull);
      expect(Validators.cardName(null), isNotNull);
    });

    test('el formateador agrupa de 4 en 4 y corta en 16 dígitos', () {
      final r = CardNumberFormatter().formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '42424242a4242424299'),
      );
      expect(r.text, '4242 4242 4242 4242');
      expect(cardBrand('4242'), 'Visa');
      expect(cardBrand(''), '');
    });
  });
}
