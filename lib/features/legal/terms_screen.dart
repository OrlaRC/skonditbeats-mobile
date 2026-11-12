import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Mismo contenido que /terminos de la versión web.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _intro =
      'Estos Términos y Condiciones regulan el acceso y uso de la plataforma SkonditBeats '
      '(en adelante "la Plataforma"), operada para la compra, venta y distribución de beats '
      'musicales. Al registrarte o utilizar cualquiera de nuestros servicios, aceptas '
      'íntegramente los términos aquí descritos. Si no estás de acuerdo con ellos, te pedimos '
      'que no utilices la Plataforma.';

  static const _secciones = <(String, List<String>)>[
    ('1. Aceptación de los términos', [
      'Al crear una cuenta, iniciar sesión, comprar un beat o un paquete, o utilizar cualquier '
          'funcionalidad de SkonditBeats, declaras que tienes la mayoría de edad legal en tu país '
          'de residencia y que aceptas estos términos de forma libre, expresa e informada.',
    ]),
    ('2. Cuentas de usuario', [
      '2.1. Para acceder a ciertos servicios es necesario crear una cuenta con un correo '
          'electrónico válido y una contraseña segura. Eres responsable de la confidencialidad de '
          'tus credenciales y de todas las actividades realizadas con tu cuenta.',
      '2.2. La información proporcionada debe ser veraz y completa. SkonditBeats se reserva el '
          'derecho de suspender o eliminar cuentas que incumplan estos términos o que se registren '
          'con datos falsos.',
    ]),
    ('3. Uso de la Plataforma', [
      '3.1. Te comprometes a utilizar la Plataforma únicamente con fines legales y de acuerdo con '
          'estos términos, sin infringir derechos de terceros ni las leyes aplicables.',
      '3.2. Queda prohibido: intentar vulnerar la seguridad del sistema, acceder a información '
          'ajena, reproducir el contenido de la Plataforma sin autorización, o realizar cualquier '
          'actividad que pueda dañar o interrumpir su funcionamiento.',
    ]),
    ('4. Compra de beats y paquetes', [
      '4.1. Los beats y paquetes ("Packs") se ofrecen mediante una licencia de uso digital. Al '
          'completar tu compra y recibir el código de verificación, obtienes una licencia personal, '
          'no exclusiva e intransferible para utilizar el material de acuerdo con la licencia adquirida.',
      '4.2. La compra es final. Una vez entregado el material digital, no se aceptan devoluciones '
          'salvo disposición legal aplicable o fallo técnico comprobado de entrega.',
      '4.3. Cada transacción es registrada en la bitácora de la Plataforma para fines de auditoría '
          'y seguridad.',
    ]),
    ('5. Propiedad intelectual', [
      '5.1. Todo el contenido de la Plataforma —incluyendo beats, arte, textos, logotipos, código y '
          'diseño— está protegido por las leyes de propiedad intelectual. Queda prohibida su '
          'reproducción, distribución o explotación sin el consentimiento expreso de sus titulares.',
      '5.2. El usuario que adquiere un beat conserva los derechos sobre sus propias composiciones, '
          'pero no sobre el audio o los elementos de la licencia que no estén expresamente incluidos.',
    ]),
    ('6. Privacidad y protección de datos', [
      '6.1. Tratamos tus datos personales conforme a nuestra Política de Privacidad. La información '
          'recabada se utiliza exclusivamente para la prestación del servicio, la gestión de tu '
          'cuenta y el cumplimiento de obligaciones legales.',
      '6.2. No vendemos ni compartimos tus datos personales con terceros, salvo lo necesario para el '
          'funcionamiento de la Plataforma (por ejemplo, proveedores de correo o pagos) o cuando lo '
          'exija la ley.',
    ]),
    ('7. Uso de códigos de verificación (OTP)', [
      '7.1. Para proteger tu cuenta, los inicios de sesión pueden requerir un código de verificación '
          'enviado a tu correo electrónico. Dicho código es de uso personal e intransferible y expira '
          'a los pocos minutos de ser generado.',
      '7.2. No compartas tu código con nadie. SkonditBeats nunca te solicitará tu código por '
          'teléfono, mensaje u otro medio.',
    ]),
    ('8. Limitación de responsabilidad', [
      'SkonditBeats se esfuerza por ofrecer un servicio continuo y de calidad, pero no garantiza la '
          'disponibilidad ininterrumpida de la Plataforma. No seremos responsables por daños '
          'indirectos, pérdida de datos o lucro cesante derivados del uso o la imposibilidad de uso '
          'del servicio, en la medida máxima permitida por la ley.',
    ]),
    ('9. Modificaciones', [
      'Nos reservamos el derecho de actualizar estos términos en cualquier momento. Los cambios '
          'serán notificados mediante la publicación de la nueva versión en la Plataforma, indicando '
          'la fecha de última actualización. El uso continuado del servicio tras dichos cambios '
          'constituye tu aceptación.',
    ]),
    ('10. Legislación aplicable y contacto', [
      'Estos términos se rigen por la legislación de los Estados Unidos Mexicanos. Para cualquier '
          'duda, aclaración o reclamación, puedes contactarnos a través de la sección de Contacto de '
          'la Plataforma.',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(color: Color(0xFFD4D4D4), height: 1.5);
    final heading = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700);

    return Scaffold(
      appBar: AppBar(title: const Text('Términos y condiciones')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text('Última actualización: 11 de agosto de 2026',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            const Text(_intro, style: body),
            for (final (titulo, parrafos) in _secciones) ...[
              const SizedBox(height: 24),
              Semantics(header: true, child: Text(titulo, style: heading)),
              for (final p in parrafos) ...[
                const SizedBox(height: 8),
                Text(p, style: body),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
