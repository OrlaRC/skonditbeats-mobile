import 'package:flutter/services.dart';

/// "4242424242424242" → "4242 4242 4242 4242"
class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 16 ? digits.substring(0, 16) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(limited[i]);
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// "1228" → "12/28"
class CardExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 4) digits = digits.substring(0, 4);
    // Al borrar la "/" no se vuelve a insertar de inmediato.
    final borrando = newValue.text.length < oldValue.text.length;
    final text = digits.length > 2 || (digits.length == 2 && !borrando)
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Marca de la tarjeta según el primer dígito (solo informativo).
String cardBrand(String number) => switch (number.isEmpty ? '' : number[0]) {
      '4' => 'Visa',
      '5' => 'Mastercard',
      '3' => 'American Express',
      _ => '',
    };
