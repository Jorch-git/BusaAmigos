
/// Estado actual del transporte.
enum TransportState {
  /// No iniciado o detenido.
  idle,

  /// Intentando establecer conexión (relay alcanzable, peers detectados...).
  connecting,

  /// Operativo. Mensajes pueden fluir.
  connected,

  /// Operando solo en local (sin servidor) o sin peers. Aún recibe entradas
  /// nuevas si llegan.
  degraded,

  /// Hubo un error que requiere reintentar.
  error,
}

/// Capacidad del transporte de alcanzar a otros miembros.
enum TransportReach {
  /// Internet/relay disponible: cualquier miembro del grupo es alcanzable.
  global,

  /// Solo proximidad física: ~30–100 m vía mesh local.
  local,

  /// Sin nadie alcanzable.
  none,
}

/// Interfaz del transporte. Las implementaciones concretas son:
///  - [FakeRelayTransport]    desarrollo/tests
///  - [RelayTransport]        Firebase / Supabase / backend propio
///  - [NearbyTransport]       Google Nearby / MultipeerConnectivity
///
/// La idea es que la UI solo conozca esta interfaz. Cambiar de proveedor
/// significa enchufar otra implementación, no tocar pantallas.
abstract class TransportService {
  /// Stream del estado actual.
  Stream<TransportState> get stateStream;
  TransportState get currentState;

  /// Stream de los mensajes entrantes (ya descifrados por la capa superior
  /// — el transporte mueve bytes, GroupController los descifra).
  ///
  /// Lo que llega aquí son blobs cifrados base64 listos para
  /// [GroupCrypto.decryptJson].
  Stream<String> get incomingStream;

  /// Capacidad actual de alcance.
  TransportReach get reach;

  /// Inicia el transporte para el grupo identificado por [groupCode].
  /// El transporte NO necesita la clave criptográfica — se le pasa solo
  /// el código (que es el "channel id" público).
  Future<void> start({required String groupCode, required String selfId});

  /// Envía un blob cifrado a todos los demás miembros del grupo.
  /// El transporte no entiende qué hay dentro, solo lo entrega.
  ///
  /// [reliable]: si es true, el transporte intentará garantizar la entrega
  /// (ACK + reintentos en la capa mesh). Se usa para chat y SOS. Las
  /// posiciones van con reliable=false porque se renuevan constantemente.
  /// Las implementaciones que no soportan fiabilidad simplemente ignoran el
  /// flag y entregan best-effort.
  Future<void> send(String encryptedBlob, {bool reliable = false});

  /// Detiene el transporte y libera recursos.
  Future<void> stop();
}
