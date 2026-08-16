/// Deriva un identificador CORTO y estable a partir del id largo del miembro
/// (que es un UUID de 36 caracteres, imposible de meter en un anuncio BLE).
///
/// Un anuncio BLE tiene ~20-26 bytes útiles, así que no cabe un UUID. La
/// solución: derivar un número de 16 bits (0-65535) del UUID con un hash
/// determinista. Lo metemos como "manufacturer data" o en el nombre del
/// servicio. Cuando escaneamos y vemos ese número, lo comparamos contra los
/// ids cortos de los miembros del grupo para saber quién es quién.
///
/// Colisión: con 16 bits hay 65536 valores posibles. Para grupos de ≤10
/// personas la probabilidad de que dos compartan id corto es mínima
/// (~0.07%). Suficiente para festivales. Si dos colisionaran, el peor caso
/// es que el RSSI de uno se le atribuya al otro; el GPS lo corregiría.
class ShortId {
  /// Convierte un memberId (UUID) en un entero de 16 bits estable.
  static int of(String memberId) {
    // FNV-1a hash de 32 bits, truncado a 16 bits. Determinista: el mismo
    // memberId siempre da el mismo short id, en cualquier dispositivo.
    var hash = 0x811c9dc5;
    for (var i = 0; i < memberId.length; i++) {
      hash ^= memberId.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0xffff; // 16 bits
  }

  /// Los dos bytes del short id (para meter en manufacturer data).
  static List<int> bytesOf(String memberId) {
    final id = of(memberId);
    return [(id >> 8) & 0xff, id & 0xff];
  }

  /// Reconstruye el short id desde dos bytes.
  static int fromBytes(int hi, int lo) => ((hi & 0xff) << 8) | (lo & 0xff);
}
