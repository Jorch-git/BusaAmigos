/// Sobre de enrutamiento del mesh.
///
/// IMPORTANTE: la cabecera (id, origin, ttl, hop, flags) viaja EN CLARO porque
/// los nodos intermedios necesitan leerla para reenviar sin descifrar nada. El
/// [payload] es el blob ya cifrado E2E por [PayloadCodec]: para los nodos que
/// reenvían es ruido opaco. Es el mismo principio que usa Bridgefy: el relay
/// ve metadatos de ruteo, jamás el contenido.
///
/// v20: se añade el campo [reliable] (0/1) y un segundo tipo de sobre, el ACK.
///  - Si reliable=1, el ORIGEN reintenta el mensaje hasta recibir un ACK del
///    destino (chat, SOS). Así "no se pierde la información" aunque la
///    topología de la malla cambie en el momento del primer envío.
///  - El ACK es un sobre liviano que confirma "recibí el mensaje con id X".
///    Viaja por la misma malla (multi-hop) de vuelta al origen.
///
/// Formato del sobre de DATOS (delimitado, para minimizar bytes):
///   M1|{id}|{origin}|{ttl}|{hop}|{reliable}|{payload}
///
/// Formato del sobre de ACK:
///   A1|{ackId}|{origin}|{ttl}|{hop}|{ackedId}
///   donde ackedId es el id del mensaje que se está confirmando, y origin es
///   quién emite el ACK (el destinatario que recibió el mensaje).
///
/// El payload es base64Url (alfabeto A–Z a–z 0–9 - _), que no contiene '|',
/// así que el parseo por '|' es seguro.
class MeshEnvelope {
  static const String magic = 'M1';

  final String id; // identificador único del mensaje (no del sobre)
  final String origin; // selfId de quien lo originó
  final int ttl; // saltos restantes
  final int hop; // saltos dados
  final bool reliable; // ¿requiere ACK + reintentos?
  final String payload; // blob cifrado E2E

  const MeshEnvelope({
    required this.id,
    required this.origin,
    required this.ttl,
    required this.hop,
    required this.reliable,
    required this.payload,
  });

  String encode() =>
      '$magic|$id|$origin|$ttl|$hop|${reliable ? 1 : 0}|$payload';

  /// Devuelve `null` si la cadena no es un sobre mesh de datos válido.
  static MeshEnvelope? tryParse(String raw) {
    if (!raw.startsWith('$magic|')) return null;
    final parts = raw.split('|');
    if (parts.length < 7) return null;
    final ttl = int.tryParse(parts[3]);
    final hop = int.tryParse(parts[4]);
    final rel = parts[5];
    if (ttl == null || hop == null) return null;
    // El payload no contiene '|', pero por robustez reunimos lo que reste.
    final payload = parts.sublist(6).join('|');
    return MeshEnvelope(
      id: parts[1],
      origin: parts[2],
      ttl: ttl,
      hop: hop,
      reliable: rel == '1',
      payload: payload,
    );
  }

  MeshEnvelope forwarded() => MeshEnvelope(
      id: id,
      origin: origin,
      ttl: ttl - 1,
      hop: hop + 1,
      reliable: reliable,
      payload: payload);
}

/// Sobre de confirmación (ACK). Confirma que [ackedId] fue recibido por su
/// destinatario. Viaja por la malla multi-hop hasta el origen del mensaje.
class MeshAck {
  static const String magic = 'A1';

  final String ackId; // id único del propio ACK (para dedupe)
  final String origin; // quién emite el ACK (el que recibió el mensaje)
  final int ttl;
  final int hop;
  final String ackedId; // id del mensaje que se confirma

  const MeshAck({
    required this.ackId,
    required this.origin,
    required this.ttl,
    required this.hop,
    required this.ackedId,
  });

  String encode() => '$magic|$ackId|$origin|$ttl|$hop|$ackedId';

  static MeshAck? tryParse(String raw) {
    if (!raw.startsWith('$magic|')) return null;
    final parts = raw.split('|');
    if (parts.length < 6) return null;
    final ttl = int.tryParse(parts[3]);
    final hop = int.tryParse(parts[4]);
    if (ttl == null || hop == null) return null;
    return MeshAck(
      ackId: parts[1],
      origin: parts[2],
      ttl: ttl,
      hop: hop,
      ackedId: parts[5],
    );
  }

  MeshAck forwarded() => MeshAck(
      ackId: ackId,
      origin: origin,
      ttl: ttl - 1,
      hop: hop + 1,
      ackedId: ackedId);
}
