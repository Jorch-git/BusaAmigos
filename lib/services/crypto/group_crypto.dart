import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'group_code.dart';

/// Cifrado simétrico de extremo a extremo para el grupo.
///
/// Modelo de amenaza: el servidor relay o cualquier nodo intermedio del
/// mesh NO debe poder leer el contenido. Solo los miembros que conocen el
/// código del grupo pueden descifrar.
///
/// Diseño:
///  - Clave de 32 bytes derivada del código vía Argon2id. Salt fijo público
///    derivado del propio código (el código MISMO es el secreto).
///  - AEAD XChaCha20-Poly1305: nonce de 24 bytes aleatorio por mensaje y tag
///    de autenticación de 16 bytes.
///
/// Esta versión expone además [encryptBytes]/[decryptBytes] para que la capa
/// de compresión ([PayloadCodec]) pueda cifrar bytes ya comprimidos sin pasar
/// por JSON.
class GroupCrypto {
  final SecretKey _key;
  final Cipher _cipher;

  GroupCrypto._(this._key) : _cipher = Xchacha20.poly1305Aead();

  static Future<GroupCrypto> deriveFromCode(String code) async {
    final normalized = GroupCode.normalize(code);
    final passwordBytes = utf8.encode(normalized);

    final saltSource = utf8.encode('buscamigos.salt.v1.$normalized');
    final saltDigest = await Sha256().hash(saltSource);
    final salt = Uint8List.fromList(saltDigest.bytes.sublist(0, 16));

    final kdf = Argon2id(
      memory: 19456,
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

  /// Cifra bytes crudos. Devuelve base64Url(nonce + ct + mac).
  Future<String> encryptBytes(List<int> plaintext) async {
    final box = await _cipher.encrypt(plaintext, secretKey: _key);
    final out = BytesBuilder()
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return base64Url.encode(out.toBytes());
  }

  /// Descifra el blob producido por [encryptBytes]. `null` si la
  /// autenticación falla (clave incorrecta o mensaje manipulado).
  Future<Uint8List?> decryptBytes(String blob) async {
    try {
      final bytes = base64Url.decode(blob);
      const nonceLen = 24;
      const macLen = 16;
      if (bytes.length < nonceLen + macLen) return null;

      final nonce = bytes.sublist(0, nonceLen);
      final cipherText = bytes.sublist(nonceLen, bytes.length - macLen);
      final macBytes = bytes.sublist(bytes.length - macLen);

      final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final decrypted = await _cipher.decrypt(box, secretKey: _key);
      return Uint8List.fromList(decrypted);
    } on SecretBoxAuthenticationError {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Conveniencia: cifra un mapa JSON sin compresión (compatibilidad con el
  /// código previo). Para minimizar datos, usa [PayloadCodec].
  Future<String> encryptJson(Map<String, dynamic> payload) async {
    return encryptBytes(utf8.encode(jsonEncode(payload)));
  }

  Future<Map<String, dynamic>?> decryptJson(String blob) async {
    final bytes = await decryptBytes(blob);
    if (bytes == null) return null;
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Huella corta de la clave (no la clave). Para verificar visualmente que
  /// dos celulares derivaron la misma clave.
  Future<String> fingerprint() async {
    final keyBytes = await _key.extractBytes();
    final digest = await Sha256().hash(keyBytes);
    return digest.bytes
        .take(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }
}
