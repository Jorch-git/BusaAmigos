import 'dart:math';

/// Genera y valida códigos de grupo legibles tipo `FMO-482KL3`.
///
/// Diseño: 9 caracteres del alfabeto Crockford-Base32 (sin I, L, O, U para
/// evitar confusiones), divididos como `XXX-XXXXXX` para que sea fácil
/// dictarlo. Eso da ~6×10^13 combinaciones, suficiente para que dos grupos
/// activos no choquen sin necesitar autoridad central.
///
/// Importante: este código es DOBLE PROPÓSITO:
///  1. Identificador del grupo en el relay/mesh (todos los miembros lo
///     comparten para encontrarse).
///  2. Material del que se deriva la clave de cifrado en [GroupCrypto].
///
/// Por eso la entropía importa: nadie debería poder adivinarlo y entrar al
/// grupo. 9 caracteres × log2(32) ≈ 45 bits, suficiente para resistir
/// adivinanza online (no adivinanza offline, pero como nunca se publica
/// el código en claro junto a contenido cifrado, eso da igual).
class GroupCode {
  /// Crockford Base32 sin I, L, O, U.
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static final RegExp _validator = RegExp(r'^[0-9A-HJKMNP-TV-Z]{3}-[0-9A-HJKMNP-TV-Z]{6}$');

  /// Genera un nuevo código aleatorio. Usa `Random.secure()`.
  static String generate() {
    final rng = Random.secure();
    final left = List.generate(3, (_) => _alphabet[rng.nextInt(32)]).join();
    final right = List.generate(6, (_) => _alphabet[rng.nextInt(32)]).join();
    return '$left-$right';
  }

  /// Normaliza a mayúsculas y limpia espacios. NO valida formato.
  static String normalize(String input) {
    return input
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        // mapea letras ambiguas a sus equivalentes Crockford
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('O', '0')
        .replaceAll('U', 'V');
  }

  /// `true` si el código tiene el formato esperado.
  static bool isValid(String input) {
    return _validator.hasMatch(normalize(input));
  }

  /// Convierte el código en bytes para uso criptográfico (después del KDF).
  /// Quita el guion y devuelve UTF-8.
  static List<int> toBytes(String code) {
    return normalize(code).replaceAll('-', '').codeUnits;
  }
}
