import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/utils/validators.dart';

void main() {
  group('Validators.password (misma política que el backend)', () {
    test('rechaza contraseñas cortas o incompletas', () {
      expect(Validators.password('Abc1!'), isNotNull);
      expect(Validators.password('abcdefghij1!'), isNotNull); // sin mayúscula
      expect(Validators.password('ABCDEFGHIJ1!'), isNotNull); // sin minúscula
      expect(Validators.password('Abcdefghij!'), isNotNull); // sin número
      expect(Validators.password('Abcdefghij1'), isNotNull); // sin especial
    });

    test('acepta una contraseña que cumple todo', () {
      expect(Validators.password('Skondit2026!'), isNull);
    });
  });

  test('email', () {
    expect(Validators.email('no-es-correo'), isNotNull);
    expect(Validators.email('cliente@skondit.com'), isNull);
  });

  test('edad mínima 18', () {
    expect(Validators.age('17'), isNotNull);
    expect(Validators.age('18'), isNull);
  });

  test('otp de 6 dígitos', () {
    expect(Validators.otp('12345'), isNotNull);
    expect(Validators.otp('123456'), isNull);
  });
}
