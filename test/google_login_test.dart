// Inicio de sesión con Google desde la app: interpretación del regreso
// skonditbeats://login?... que manda la API al terminar el OAuth.
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/network/api_client.dart';
import 'package:skondit_beats_mobile/features/auth/data/auth_repository.dart';

void main() {
  test('regreso correcto → pide el OTP con el correo de Google', () {
    final r = leerRegresoGoogle(Uri.parse('skonditbeats://login?google=1&email=ana%40uteq.edu.mx'));
    expect(r.email, 'ana@uteq.edu.mx');
    expect(r.otpDev, isNull);
  });

  test('en desarrollo puede traer otpDev', () {
    final r = leerRegresoGoogle(Uri.parse('skonditbeats://login?google=1&email=a%40b.co&otpDev=123456'));
    expect(r.otpDev, '123456');
  });

  test('cada error conocido se traduce y uno desconocido cae en el genérico', () {
    expect(() => leerRegresoGoogle(Uri.parse('skonditbeats://login?error=google_cancelled')),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Cancelaste'))));
    expect(() => leerRegresoGoogle(Uri.parse('skonditbeats://login?error=account_disabled')),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('desactivada'))));
    expect(() => leerRegresoGoogle(Uri.parse('skonditbeats://login?error=otra_cosa')),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('No se pudo'))));
  });

  test('sin correo o con otro esquema se rechaza', () {
    expect(() => leerRegresoGoogle(Uri.parse('skonditbeats://login?google=1')), throwsA(isA<ApiException>()));
    expect(() => leerRegresoGoogle(Uri.parse('https://evil.example/login?email=a%40b.co')), throwsA(isA<ApiException>()));
  });
}
