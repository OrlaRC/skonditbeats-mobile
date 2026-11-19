// Prácticas 13 y 14 · AUT-04 (integración) · Servicio: AuthRepository ↔ API /api/auth.
// La app manda la petición real (Dio + interceptor de reintentos de la app) a un
// servidor HTTP local que responde como la API de SkonditBeats.
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/network/api_client.dart';
import 'package:skondit_beats_mobile/features/auth/data/auth_repository.dart';

import 'apoyo/servidor_prueba.dart';

const usuarioAdmin = {'id': 'u-admin', 'email': 'admin@local.test', 'nombre': 'Admin', 'rol': 'ADMIN'};

void main() {
  late ServidorPrueba api;
  late AuthRepository repo;

  setUp(() async {
    api = ServidorPrueba();
    await api.iniciar();
    repo = AuthRepository(dioDePrueba(api.url));
  });
  tearDown(() => api.cerrar());

  test('AUT-04a · login de admin: envía JSON normalizado y recibe token + usuario (200)', () async {
    api.responder = (r) => (status: 200, cuerpo: {'token': 'jwt-123', 'user': usuarioAdmin});

    final r = await repo.login('  Admin@Local.TEST ', 'Prueba-12345!');

    expect(r, isA<LoginSuccess>());
    final ok = r as LoginSuccess;
    expect(ok.token, 'jwt-123');
    expect(ok.user.isAdmin, isTrue);
    // Lo que llegó al servidor:
    final p = api.recibidas.single;
    expect(p.metodo, 'POST');
    expect(p.ruta, '/api/auth/login');
    expect(p.cabeceras.contentType?.mimeType, 'application/json');
    expect(p.cuerpo, {'email': 'admin@local.test', 'password': 'Prueba-12345!'});
  });

  test('AUT-04b · login de cliente: la API pide 2FA y la app pasa al OTP', () async {
    api.responder = (r) => (
          status: 200,
          cuerpo: {'requires2fa': true, 'email': 'cliente@local.test', 'otpDev': '654321'},
        );

    final r = await repo.login('cliente@local.test', 'Prueba-12345!');

    expect(r, isA<LoginNeedsOtp>());
    expect((r as LoginNeedsOtp).otpDev, '654321');
    expect(r.message, 'Código enviado a tu correo'); // la API no mandó mensaje
  });

  test('AUT-04c · verificar OTP → sesión del cliente', () async {
    api.responder = (r) => (
          status: 200,
          cuerpo: {
            'token': 'jwt-cli',
            'user': {'id': 'u-cli', 'email': 'cliente@local.test', 'nombre': 'Cliente'},
          },
        );

    final r = await repo.verifyOtp('cliente@local.test', '654321');

    expect(api.recibidas.single.ruta, '/api/auth/verify-otp');
    expect(api.recibidas.single.cuerpo, {'email': 'cliente@local.test', 'code': '654321'});
    expect(r.user.rol, 'CLIENTE'); // sin rol → cliente
    expect(r.user.isAdmin, isFalse);
  });

  test('AUT-04d · contraseña incorrecta: 401 con el mensaje de la API y sin reintentos', () async {
    api.responder = (r) => (status: 401, cuerpo: {'error': 'Correo o contraseña incorrectos'});

    await expectLater(
      repo.login('admin@local.test', 'mala'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 401)
          .having((e) => e.message, 'mensaje', 'Correo o contraseña incorrectos')),
    );
    expect(api.recibidas, hasLength(1)); // un 401 no es transitorio
  });

  test('AUT-04e · registro con correo repetido: 409 y mensaje claro', () async {
    api.responder = (r) => (status: 409, cuerpo: {'error': 'Ese correo ya está registrado'});

    await expectLater(
      repo.register(const RegisterData(nombre: 'Ana', email: 'ana@mail.com', password: 'Skondit2026!', edad: 20)),
      throwsA(isA<ApiException>().having((e) => e.message, 'mensaje', 'Ese correo ya está registrado')),
    );
    expect(api.recibidas.single.ruta, '/api/auth/register');
  });

  test('AUT-04f · registro correcto: 201 con token y el usuario creado', () async {
    api.responder = (r) => (
          status: 201,
          cuerpo: {
            'token': 'jwt-nuevo',
            'user': {'id': 'u-9', 'email': r.cuerpo!['email'], 'nombre': r.cuerpo!['nombre'], 'rol': 'CLIENTE'},
          },
        );

    final r = await repo.register(
        const RegisterData(nombre: ' Ana ', email: 'ANA@mail.com', password: 'Skondit2026!', edad: 20));

    expect(r.token, 'jwt-nuevo');
    expect(r.user.email, 'ana@mail.com');
    expect(r.user.nombre, 'Ana');
  });

  test('AUT-04g · respuesta 200 incompleta (sin token): error controlado, no TypeError', () async {
    // Un proxy, una versión vieja de la API o una caché pueden contestar 200 con otro cuerpo.
    api.responder = (r) => (status: 200, cuerpo: {'ok': true});

    await expectLater(repo.login('admin@local.test', 'Prueba-12345!'), throwsA(isA<ApiException>()));
    await expectLater(repo.verifyOtp('a@b.com', '123456'), throwsA(isA<ApiException>()));
  });

  test('AUT-04h · respuesta 200 que no es JSON (página HTML): error controlado', () async {
    api.responder = (r) => (status: 200, cuerpo: '<html>Portal cautivo</html>');

    await expectLater(repo.login('admin@local.test', 'Prueba-12345!'), throwsA(isA<ApiException>()));
  });

  test('AUT-04i · 503 en el login (POST sin Idempotency-Key): no se repite a ciegas', () async {
    var n = 0;
    api.responder = (r) => ++n < 3
        ? (status: 503, cuerpo: {'statusCode': 503, 'error': 'Service Unavailable'})
        : (status: 200, cuerpo: {'token': 'jwt', 'user': usuarioAdmin});

    // El login es POST: solo se reintenta si lleva Idempotency-Key. Sin clave no debe repetirse.
    await expectLater(repo.login('admin@local.test', 'x'), throwsA(isA<ApiException>()));
    expect(api.recibidas, hasLength(1));
  });
}
