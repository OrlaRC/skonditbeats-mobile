// Prácticas 13 y 14 · AUT-05 (integración) · Pantalla de inicio de sesión ↔ controlador
// ↔ repositorio ↔ red. Se monta la LoginScreen real; solo se cambia la URL de la API
// por un servidor local (o por un puerto donde no escucha nadie).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/core/network/api_client.dart';
import 'package:skondit_beats_mobile/features/auth/presentation/auth_controller.dart';
import 'package:skondit_beats_mobile/features/auth/presentation/screens/login_screen.dart';

import 'apoyo/servidor_prueba.dart';

/// Controlador real, pero arranca "sin sesión" en lugar de leer el almacenamiento seguro.
class SinSesionGuardada extends AuthController {
  @override
  AuthState build() => const AuthState.unauthenticated();
}

Future<void> montar(WidgetTester t, String apiUrl) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(SinSesionGuardada.new),
      dioProvider.overrideWithValue(dioDePrueba(apiUrl, timeout: const Duration(milliseconds: 600))),
    ],
    child: const MaterialApp(home: LoginScreen()),
  ));
}

Future<void> capturarYEnviar(WidgetTester t, {String email = 'admin@local.test', String pass = 'Prueba-12345!'}) async {
  await t.enterText(find.widgetWithText(TextFormField, 'Correo electrónico'), email);
  await t.enterText(find.widgetWithText(TextFormField, 'Contraseña'), pass);
  // La petición se lanza en la zona real (no en el reloj falso) para que los sockets
  // y los timeouts de Dio corran con tiempo real.
  await t.runAsync(() async => t.tap(find.text('Iniciar sesión')));
  await t.pump();
}

/// Las peticiones HTTP reales no avanzan con el reloj falso de las pruebas de widgets:
/// se deja correr el tiempo real hasta que aparezca [texto].
Future<void> esperarTexto(WidgetTester t, Pattern texto) async {
  for (var i = 0; i < 300; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    final hay = texto is String ? find.text(texto) : find.textContaining(texto);
    if (hay.evaluate().isNotEmpty) return;
  }
  final textos = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join(' | ');
  fail('No apareció el mensaje "$texto" en pantalla. Había: $textos');
}

void main() {
  // testWidgets instala un HttpClient falso que responde 400 a todo (para imágenes de
  // red). Aquí se quiere la red real hacia 127.0.0.1, así que se quita.
  setUp(() => HttpOverrides.global = null);

  testWidgets('AUT-05a · servidor apagado → aviso de que no hay conexión y el botón se reactiva',
      (t) async {
    await montar(t, await t.runAsync(urlSinServidor) as String);

    await capturarYEnviar(t);
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // cargando

    await esperarTexto(t, RegExp('Sin conexión con el servidor|El servidor tardó demasiado'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Iniciar sesión'), findsOneWidget); // se puede volver a intentar
  });

  testWidgets('AUT-05b · servidor que no contesta → aviso de tiempo agotado', (t) async {
    final api = ServidorPrueba()..responder = (_) => null; // acepta la conexión y nunca responde
    await t.runAsync(api.iniciar);
    addTearDown(() => t.runAsync(api.cerrar));
    await montar(t, api.url);

    await capturarYEnviar(t);

    await esperarTexto(t, 'El servidor tardó demasiado en responder. Intenta de nuevo.');
  });

  testWidgets('AUT-05c · credenciales incorrectas → se muestra el mensaje que manda la API', (t) async {
    final api = ServidorPrueba()..responder = (_) => (status: 401, cuerpo: {'error': 'Correo o contraseña incorrectos'});
    await t.runAsync(api.iniciar);
    addTearDown(() => t.runAsync(api.cerrar));
    await montar(t, api.url);

    await capturarYEnviar(t, pass: 'equivocada');

    await esperarTexto(t, 'Correo o contraseña incorrectos');
    expect(api.recibidas, hasLength(1));
  });

  testWidgets('AUT-05d · respuesta 200 dañada → mensaje de error, no se queda en silencio', (t) async {
    final api = ServidorPrueba()..responder = (_) => (status: 200, cuerpo: {'ok': true});
    await t.runAsync(api.iniciar);
    addTearDown(() => t.runAsync(api.cerrar));
    await montar(t, api.url);

    await capturarYEnviar(t);

    await esperarTexto(t, RegExp('respuesta.*no es válida', caseSensitive: false));
    expect(t.takeException(), isNull);
  });

  testWidgets('AUT-05e · formulario vacío → la app no llama al servidor', (t) async {
    final api = ServidorPrueba()..responder = (_) => (status: 200, cuerpo: {});
    await t.runAsync(api.iniciar);
    addTearDown(() => t.runAsync(api.cerrar));
    await montar(t, api.url);

    await t.tap(find.text('Iniciar sesión'));
    await t.pump();

    expect(find.text('El correo es obligatorio'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(api.recibidas, isEmpty);
  });
}
