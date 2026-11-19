// Prácticas 13 y 14 · AUT-03 (unitarias) · Lógica de negocio que no depende de la red:
// precios, lectura de números de la API, artículos del carrito, errores de la API
// y regreso del inicio de sesión con Google.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/network/api_client.dart';
import 'package:skondit_beats_mobile/core/utils/money.dart';
import 'package:skondit_beats_mobile/features/auth/data/auth_repository.dart';
import 'package:skondit_beats_mobile/features/cart/domain/cart_item.dart';
import 'package:skondit_beats_mobile/features/catalog/domain/beat.dart';
import 'package:skondit_beats_mobile/features/catalog/domain/pack.dart';

DioException respuesta(int status, Object? cuerpo) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: status, data: cuerpo),
    );

void main() {
  group('AUT-03 · Precios (formatMoney)', () {
    test('resultado esperado con separador de miles y redondeo', () {
      expect(formatMoney(0), r'$0 MXN');
      expect(formatMoney(300), r'$300 MXN');
      expect(formatMoney(1000), r'$1,000 MXN');
      expect(formatMoney(1234567.6), r'$1,234,568 MXN');
      expect(formatMoney(1500, currency: false), r'$1,500');
    });

    test('fuera de rango: montos negativos (reembolsos/descuentos)', () {
      expect(formatMoney(-500), r'-$500 MXN');
      expect(formatMoney(-1500), r'-$1,500 MXN');
    });

    test('manejo de excepciones: un valor no finito no tumba la pantalla', () {
      expect(() => formatMoney(double.nan), returnsNormally);
      expect(formatMoney(double.nan), r'$0 MXN');
      expect(formatMoney(double.infinity), r'$0 MXN');
    });
  });

  group('AUT-03 · Números que manda la API (parseNum)', () {
    test('número o texto válido', () {
      expect(parseNum(300), 300);
      expect(parseNum('300'), 300);
      expect(parseNum('299.90'), 299.9);
    });

    test('nulo, vacío o basura → 0', () {
      for (final v in [null, '', 'abc', <String>[]]) {
        expect(parseNum(v), 0, reason: 'valor: $v');
      }
    });

    test('texto "NaN" o "Infinity" → 0 (no es un precio)', () {
      expect(parseNum('NaN'), 0);
      expect(parseNum('Infinity'), 0);
      expect(parseNum(double.nan), 0);
    });
  });

  group('AUT-03 · Artículo del carrito (lo que se guarda en SQLite)', () {
    final b = Beat(id: 'b1', nombre: 'Noche', genero: 'Trap', bpm: 140, precio: 300);

    test('un beat ida y vuelta por toMap/fromMap queda igual', () {
      final item = CartItem.fromBeat(b);
      final leido = CartItem.fromMap(item.toMap('u1'));
      expect(leido.itemId, 'b1');
      expect(leido.tipo, CartItemType.beat);
      expect(leido.detalle, 'Trap · 140 BPM');
      expect(leido.precio, 300);
      expect(leido.beatIds, ['b1']);
      expect(leido.agregado, item.agregado);
    });

    test('un paquete vacío se guarda sin ids fantasma', () {
      final p = Pack(id: 'p1', nombre: 'Vacío', precio: 0, beats: const []);
      final leido = CartItem.fromMap(CartItem.fromPack(p).toMap('u1'));
      expect(leido.isPack, isTrue);
      expect(leido.beatIds, isEmpty);
    });
  });

  group('AUT-03 · Mensajes de error de la API (ApiException.fromDio)', () {
    test('usa el mensaje de la API cuando lo trae', () {
      final e = ApiException.fromDio(respuesta(401, {'error': 'Credenciales inválidas'}));
      expect(e.message, 'Credenciales inválidas');
      expect(e.statusCode, 401);
    });

    test('no muestra el inglés de Fastify (Práctica 11, DEF-01)', () {
      final e = ApiException.fromDio(respuesta(400, {'statusCode': 400, 'error': 'Bad Request'}));
      expect(e.message, 'Revisa los datos e intenta de nuevo.');
    });

    test('código HTTP → mensaje para el usuario', () {
      expect(ApiException.fromDio(respuesta(403, null)).message, 'No tienes permiso para hacer esto.');
      expect(ApiException.fromDio(respuesta(404, null)).message, 'No se encontró lo que buscabas.');
      expect(ApiException.fromDio(respuesta(503, '<html>')).message, contains('(503)'));
    });
  });

  group('AUT-03 · Regreso del inicio de sesión con Google', () {
    test('entrada válida → pide el OTP del correo', () {
      final r = leerRegresoGoogle(Uri.parse('skonditbeats://login?google=1&email=a%40b.com&otpDev=123456'));
      expect(r.email, 'a@b.com');
      expect(r.otpDev, '123456');
    });

    test('manejo de excepciones: error, correo vacío u otro esquema → ApiException', () {
      expect(() => leerRegresoGoogle(Uri.parse('skonditbeats://login?error=google_cancelled')),
          throwsA(isA<ApiException>().having((e) => e.message, 'mensaje', contains('Cancelaste'))));
      expect(() => leerRegresoGoogle(Uri.parse('skonditbeats://login?error=desconocido')),
          throwsA(isA<ApiException>()));
      expect(() => leerRegresoGoogle(Uri.parse('skonditbeats://login?email=')), throwsA(isA<ApiException>()));
      expect(() => leerRegresoGoogle(Uri.parse('https://otra.app/login?email=a@b.com')),
          throwsA(isA<ApiException>()));
    });
  });
}
