import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'group_code.dart';

/// Cifrado simétrico de extremo a extremo para el grupo.
///
/// Modelo de amenaza: el servidor relay (cuando exista) o cualquier nodo
/// intermedio en el mesh local NO debe poder leer el contenido — ni
/// posiciones ni mensajes ni alertas SOS. Solo los miembros que conocen
/// el código del grupo pueden descifrar.
///
/// Diseño:
///  - Clave de 32 bytes derivada del código vía Argon2id (resistente a
///    fuerza bruta con GPU). Salt fijo público derivado del propio código:
///    como el código tiene ~45 bits de entropía y es secreto, no necesitamos
///    salt aleatorio — el código MISMO es el secreto. El salt fijo asegura
///    que dos celulares con el mismo código deriven la misma clave.
///  - AEAD con XChaCha20-Poly1305: nonce de 24 bytes aleatorio por mensaje
///    (sin riesgo realista de colisión incluso con muchos millones de
///    mensajes), y tag de autenticación que detecta cualquier manipulación.
///
/// Nota sobre Argon2id: el paquete `cryptography` lo expone vía
/// `Argon2id`. Es MUCHO más lento que un HKDF puro (decenas de ms), pero
/// solo se ejecuta UNA VEZ al unirse/abrir el grupo. La clave derivada se
/// guarda en memoria (nunca en disco) y se usa para cifrar/descifrar todos
/// los mensajes subsiguientes a velocidad de stream cipher.
class GroupCrypto {
  /// Clave simétrica de 32 bytes. NUNCA persistir.
  final SecretKey _key;
  final Cipher _cipher;

  GroupCrypto._(this._key) : _cipher = Xchacha20.poly1305Aead();

  /// Deriva la clave del grupo a partir del [code].
  ///
  /// Esta operación es INTENCIONALMENTE lenta (~50–200 ms en celular
  /// moderno) para resistir fuerza bruta si alguien capturara tráfico
  /// cifrado y conociera el formato del código.
  static Future<GroupCrypto> deriveFromCode(String code) async {
    final normalized = GroupCode.normalize(code);
    final passwordBytes = utf8.encode(normalized);

    // Salt determinista derivado del propio código. No es secreto pero hace
    // que cada grupo tenga una "cadena de derivación" distinta — útil para
    // que rainbow tables prefabricadas no sirvan.
    final saltSource = utf8.encode('buscamigos.salt.v1.$normalized');
    final saltDigest = await Sha256().hash(saltSource);
    final salt = Uint8List.fromList(saltDigest.bytes.sublist(0, 16));

    final kdf = Argon2id(
      memory: 19456, // ~19 MiB, recomendación OWASP minima
      parallelism: 1,
      iterations: 2,
      hashLength: 32,
    );

    final derived = await kdf.deriveKey(
      secretKey: SecretKey(passwordBytes),
      nonce: salt,
    );

    return GroupCrypto._(derived);
  }

  /// Cifra un mapa JSON-serializable. Devuelve un blob compacto base64
  /// que incluye nonce + ciphertext + tag.
  Future<String> encryptJson(Map<String, dynamic> payload) async {
    final plaintext = utf8.encode(jsonEncode(payload));
    final box = await _cipher.encrypt(plaintext, secretKey: _key);

    // Concatenamos nonce + ct + mac y serializamos como base64.
    final out = BytesBuilder()
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return base64Url.encode(out.toBytes());
  }

  /// Descifra el blob producido por [encryptJson]. Devuelve `null` si la
  /// autenticación falla (clave incorrecta o mensaje manipulado).
  Future<Map<String, dynamic>?> decryptJson(String blob) async {
    try {
      final bytes = base64Url.decode(blob);
      // XChaCha20-Poly1305: nonce 24 bytes, mac 16 bytes
      const nonceLen = 24;
      const macLen = 16;
      if (bytes.length < nonceLen + macLen) return null;

      final nonce = bytes.sublist(0, nonceLen);
      final cipherText = bytes.sublist(nonceLen, bytes.length - macLen);
      final macBytes = bytes.sublist(bytes.length - macLen);

      final box = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );
      final decrypted = await _cipher.decrypt(box, secretKey: _key);
      return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      // Clave incorrecta o mensaje manipulado.
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Para debugging: huella corta de la clave (no la clave en sí).
  /// Útil para verificar visualmente que dos celulares derivaron la misma
  /// clave sin exponerla.
  Future<String> fingerprint() async {
    final keyBytes = await _key.extractBytes();
    final digest = await Sha256().hash(keyBytes);
    return digest.bytes
        .take(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }
}
