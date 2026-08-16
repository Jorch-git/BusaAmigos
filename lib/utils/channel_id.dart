import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Deriva el identificador de CANAL que se le manda al ancla.
///
/// POR QUÉ EXISTE ESTE ARCHIVO (es un asunto de seguridad, no de comodidad):
///
/// La clave de cifrado del grupo se deriva del código (`XXX-XXXXXX`) con
/// Argon2id. Si le mandáramos ese código en claro al ancla para que agrupe a
/// los miembros, **el ancla podría derivar la misma clave y descifrar todo**,
/// rompiendo el cifrado extremo a extremo.
///
/// Como el ancla es hardware que puede estar en manos de terceros (o ser
/// suplantado), no puede recibir el código nunca.
///
/// Solución: el canal es un hash SHA-256 del código, truncado. El ancla puede
/// agrupar correctamente a los miembros del mismo grupo, pero el hash es
/// unidireccional: del canal no se puede volver al código ni a la clave.
///
///   código de grupo  ──Argon2id──►  clave de cifrado   (solo en el celular)
///                    ──SHA-256──►   canal              (esto ve el ancla)
class ChannelId {
  ChannelId._();

  /// Cache para no recalcular el hash en cada envío.
  static final Map<String, String> _cache = {};

  /// Convierte un código de grupo en el identificador de canal público.
  /// Devuelve 16 caracteres base64Url (96 bits): suficiente para que dos
  /// grupos no colisionen jamás, y corto para caber holgado en la URL.
  static Future<String> fromGroupCode(String groupCode) async {
    final normalizado = groupCode.trim().toUpperCase();
    final enCache = _cache[normalizado];
    if (enCache != null) return enCache;

    final hash = await Sha256().hash(utf8.encode(normalizado));
    // base64Url produce A-Z a-z 0-9 - _ : todo seguro en una URL.
    final canal = base64Url.encode(hash.bytes).replaceAll('=', '').substring(0, 16);

    _cache[normalizado] = canal;
    return canal;
  }
}
