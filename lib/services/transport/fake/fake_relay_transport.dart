import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../transport_service.dart';

/// Transporte de DESARROLLO. Simula un servidor relay 100% en memoria
/// dentro del mismo proceso, y opcionalmente "miembros fantasma" que se
/// mueven solos para que puedas probar el radar sin tener 5 amigos a mano.
///
/// Cómo se usa:
///  - Cada instancia de [FakeRelayTransport] que se conecta al mismo
///    [groupCode] ve los mensajes de las demás (porque comparten el
///    [_FakeBus] estático).
///  - Si `enableGhosts` es true, después de unos segundos aparecen
///    "Juan", "Pedro", "Ana" y "María" enviando posiciones GPS falsas
///    cerca del miembro local. Útil para preview de la UI.
///
/// Cuando estés listo para producción, reemplaza esta clase por
/// [RelayTransport] (Firebase/Supabase/lo que sea) sin tocar nada más.
class FakeRelayTransport implements TransportService {
  final bool enableGhosts;

  FakeRelayTransport({this.enableGhosts = true});

  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _incomingCtrl = StreamController<String>.broadcast();

  TransportState _state = TransportState.idle;
  String? _groupCode;
  String? _selfId;
  StreamSubscription<String>? _busSub;
  Timer? _ghostTimer;

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  @override
  Stream<String> get incomingStream => _incomingCtrl.stream;

  @override
  TransportReach get reach =>
      _state == TransportState.connected ? TransportReach.global : TransportReach.none;

  void _setState(TransportState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  @override
  Future<void> start({required String groupCode, required String selfId}) async {
    if (_state != TransportState.idle) return;
    _setState(TransportState.connecting);
    _groupCode = groupCode;
    _selfId = selfId;

    // Pequeño retraso simulado.
    await Future.delayed(const Duration(milliseconds: 300));

    // Suscripción al bus compartido del código del grupo.
    _busSub = _FakeBus.instance.streamFor(groupCode).listen((message) {
      // No nos pasamos nuestros propios mensajes.
      final decoded = utf8.decode(base64Url.decode(message.split('::').first));
      final senderId = decoded;
      if (senderId == selfId) return;
      _incomingCtrl.add(message.split('::').last);
    });

    _setState(TransportState.connected);

    if (enableGhosts) {
      _startGhosts();
    }
  }

  @override
  Future<void> send(String encryptedBlob, {bool reliable = false}) async {
    if (_state != TransportState.connected) return;
    final senderTag = base64Url.encode(utf8.encode(_selfId ?? 'unknown'));
    _FakeBus.instance.publish(_groupCode!, '$senderTag::$encryptedBlob');
  }

  @override
  Future<void> stop() async {
    _ghostTimer?.cancel();
    _ghostTimer = null;
    await _busSub?.cancel();
    _busSub = null;
    _setState(TransportState.idle);
  }

  // ---------- Ghosts (miembros simulados) ----------

  /// Coordenadas GPS centrales de simulación (Ciudad de México, Foro Sol).
  /// Los ghosts giran alrededor de este punto a distancias de 8-50 m.
  static const double _ghostCenterLat = 19.4044;
  static const double _ghostCenterLng = -99.0975;

  /// "Crea" miembros fantasma publicando sus posiciones en el bus.
  /// El [GroupController] los recibirá como peers normales y los pintará.
  void _startGhosts() {
    final ghosts = _FakeGhost.defaultGhosts();
    final rng = Random();

    _ghostTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_state != TransportState.connected) {
        timer.cancel();
        return;
      }
      for (final ghost in ghosts) {
        ghost.tick(rng);
        final blob = ghost.encodePositionBlob();
        // Publicamos como si fuera otro celular.
        _FakeBus.instance.publish(
          _groupCode!,
          '${base64Url.encode(utf8.encode(ghost.id))}::$blob',
        );
      }
    });
  }
}

/// Bus singleton: dos transportes en el mismo proceso pueden comunicarse.
class _FakeBus {
  _FakeBus._();
  static final _FakeBus instance = _FakeBus._();
  final Map<String, StreamController<String>> _channels = {};

  Stream<String> streamFor(String groupCode) {
    return _channels
        .putIfAbsent(groupCode, () => StreamController.broadcast())
        .stream;
  }

  void publish(String groupCode, String wireMessage) {
    _channels[groupCode]?.add(wireMessage);
  }
}

/// Miembro simulado que se mueve solo. NO encripta — produce un blob
/// "fake-encrypted" que el descifrador real RECHAZARÁ. Pero como en
/// modo fake todos comparten el mismo [GroupCrypto] derivado del mismo
/// código, igual se descifra correctamente porque también ciframos aquí.
///
/// Realmente para que esto funcione, los ghosts tienen que cifrar. Por
/// simplicidad en este archivo dejamos un placeholder que el GroupController
/// completa: en lugar de generar blobs cifrados aquí, los ghosts publican
/// blobs que el FakeRelayTransport intercepta y reemite con la lógica del
/// GroupController. Ver `_FakeGhost.encodePositionBlob` — devuelve JSON
/// plano y el GroupController lo trata distinto si detecta el sufijo.
class _FakeGhost {
  final String id;
  final String name;
  final int colorSeed;
  double lat;
  double lng;
  double angle;
  final double radiusMeters;

  _FakeGhost({
    required this.id,
    required this.name,
    required this.colorSeed,
    required this.angle,
    required this.radiusMeters,
  })  : lat = 0,
        lng = 0 {
    _recalc();
  }

  void _recalc() {
    // 1 grado de lat ≈ 111 km. Conversión rápida para el simulador.
    final dLat = (radiusMeters * sin(angle)) / 111000;
    final dLng = (radiusMeters * cos(angle)) /
        (111000 * cos(FakeRelayTransport._ghostCenterLat * pi / 180));
    lat = FakeRelayTransport._ghostCenterLat + dLat;
    lng = FakeRelayTransport._ghostCenterLng + dLng;
  }

  void tick(Random rng) {
    angle += (rng.nextDouble() - 0.5) * 0.15;
    _recalc();
  }

  /// Empaqueta una posición en formato "fake-no-cifrado" reconocible.
  /// El controller lo identifica por el prefijo `__GHOST__:`.
  String encodePositionBlob() {
    final payload = {
      'ghost': true,
      'id': id,
      'name': name,
      'colorSeed': colorSeed,
      'lat': lat,
      'lng': lng,
      'ts': DateTime.now().toUtc().toIso8601String(),
    };
    return '__GHOST__:${base64Url.encode(utf8.encode(jsonEncode(payload)))}';
  }

  static List<_FakeGhost> defaultGhosts() => [
        _FakeGhost(id: 'ghost-juan',  name: 'Juan',  colorSeed: 0xFFEEC42E, angle: 0.0,    radiusMeters: 24),
        _FakeGhost(id: 'ghost-pedro', name: 'Pedro', colorSeed: 0xFFEEC42E, angle: pi,     radiusMeters: 15),
        _FakeGhost(id: 'ghost-ana',   name: 'Ana',   colorSeed: 0xFFE24B4A, angle: pi/3,   radiusMeters: 38),
        _FakeGhost(id: 'ghost-maria', name: 'María', colorSeed: 0xFFE24B4A, angle: 4*pi/3, radiusMeters: 42),
      ];
}
