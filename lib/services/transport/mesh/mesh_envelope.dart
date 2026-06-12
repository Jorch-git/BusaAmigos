/// Sobre de enrutamiento del mesh.
///
/// IMPORTANTE: la cabecera (id, origin, ttl, hop) viaja EN CLARO porque los
/// nodos intermedios necesitan leerla para reenviar sin descifrar nada. El
/// [payload] es el blob ya cifrado E2E por [PayloadCodec]: para los nodos que
/// reenvían es ruido opaco. Es el mismo principio que usa Bridgefy: el relay
/// ve metadatos de ruteo, jamás el contenido.
///
/// Formato en el cable (delimitado, para minimizar bytes):
///   M1|{id}|{origin}|{ttl}|{hop}|{payload}
///
/// El payload es base64Url (alfabeto A–Z a–z 0–9 - _), que no contiene '|',
/// así que el parseo por '|' es seguro.
class MeshEnvelope {
  static const String magic = 'M1';

  final String id; // identificador único del mensaje (no del sobre)
  final String origin; // selfId de quien lo originó
  final int ttl; // saltos restantes
  final int hop; // saltos dados
  final String payload; // blob cifrado E2E

  const MeshEnvelope({
    required this.id,
    required this.origin,
    required this.ttl,
    required this.hop,
    required this.payload,
  });

  String encode() => '$magic|$id|$origin|$ttl|$hop|$payload';

  /// Devuelve `null` si la cadena no es un sobre mesh válido (p. ej. un blob
  /// legacy o un ghost de desarrollo).
  static MeshEnvelope? tryParse(String raw) {
    if (!raw.startsWith('$magic|')) return null;
    final parts = raw.split('|');
    if (parts.length < 6) return null;
    final ttl = int.tryParse(parts[3]);
    final hop = int.tryParse(parts[4]);
    if (ttl == null || hop == null) return null;
    // El payload no contiene '|', pero por robustez reunimos lo que reste.
    final payload = parts.sublist(5).join('|');
    return MeshEnvelope(
      id: parts[1],
      origin: parts[2],
      ttl: ttl,
      hop: hop,
      payload: payload,
    );
  }

  MeshEnvelope forwarded() =>
      MeshEnvelope(id: id, origin: origin, ttl: ttl - 1, hop: hop + 1, payload: payload);
}
