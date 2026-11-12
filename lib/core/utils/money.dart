/// Formato de precios: 1000 → "$1,000 MXN".
String formatMoney(num value, {bool currency = true}) {
  final entero = value.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) buf.write(',');
    buf.write(entero[i]);
  }
  return '\$$buf${currency ? ' MXN' : ''}';
}

/// La API puede mandar números como texto ("300") o como número (300).
num parseNum(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
