import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../anchor/anchor_relay_transport.dart';
import '../transport_service.dart';

/// Combina la malla P2P (principal) con un ancla LilyGo (refuerzo opcional).
///
/// POR QUÉ ESTA CLASE Y NO EL HybridTransport DE SIEMPRE:
///
/// El `GroupController` decide si un mensaje se envía o se guarda en la cola
/// mirando el estado del transporte:
///
///     if (persistent && _transportState != TransportState.connected) → outbox
///
/// Si el estado combinado bajara a `degraded` solo porque no hay ancla a la
/// vista, los mensajes de chat se irían a la cola y **dejarían de enviarse**,
/// aunque la malla estuviera perfectamente conectada. Sería un bug grave
/// introducido por una mejora.
///
/// Por eso aquí la regla es explícita y conservadora:
///
///   **EL ESTADO LO MANDA SIEMPRE LA MALLA.**
///   El ancla nunca empeora el estado; solo añade un camino más.
///
/// Resultado: con ancla o sin ella, la app se comporta al menos tan bien como
/// hoy. El ancla solo puede mejorar las cosas, nunca romperlas.
class MeshPlusAnchorTransport implements TransportService {
  MeshPlusAnchorTransport(this.mesh, this.anchor);

  /// Transporte principal: la malla P2P sobre Nearby. Es quien manda.
  final TransportService mesh;

  /// Refuerzo opcional: el ancla LilyGo. Puede estar o no estar.
  final AnchorRelayTransport anchor;

  final _incomingCtrl = StreamController<String>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();

  StreamSubscription? _meshIn, _anchorIn, _meshState;

  /// Deduplicación: el mismo mensaje puede llegar por la malla Y por el ancla.
  /// Guardamos hashes recientes para entregarlo a la app una sola vez.
  final LinkedHashMap<int, DateTime> _vistos = LinkedHashMap();
  static const _ventanaDedupe = Duration(minutes: 3);
  static const _maxVistos = 400;

  int porMalla = 0, porAncla = 0, duplicados = 0;

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  /// El estado es SIEMPRE el de la malla. Ver la explicación de arriba.
  @override
  TransportState get currentState => mesh.currentState;

  @override
  Stream<String> get incomingStream => _incomingCtrl.stream;

  /// El alcance sí mejora si hay ancla: es información, no control de flujo.
  @override
  TransportReach get reach {
    if (anchor.hayAncla) return TransportReach.local;
    return mesh.reach;
  }

  @override
  Future<void> start({required String groupCode, required String selfId}) async {
    // Escuchamos ANTES de arrancar para no perder mensajes tempranos.
    _meshIn = mesh.incomingStream.listen((blob) => _entrante(blob, deMalla: true));
    _anchorIn = anchor.incomingStream.listen((blob) => _entrante(blob, deMalla: false));
    _meshState = mesh.stateStream.listen((s) {
      if (!_stateCtrl.isClosed) _stateCtrl.add(s);
    });

    await mesh.start(groupCode: groupCode, selfId: selfId);

    // El ancla se arranca aparte y NUNCA puede tumbar el arranque de la malla:
    // si falla, seguimos con malla pura.
    try {
      await anchor.start(groupCode: groupCode, selfId: selfId);
    } catch (e) {
      debugPrint('MeshPlusAnchor: el ancla no arrancó ($e); sigo con malla pura');
    }
  }

  void _entrante(String blob, {required bool deMalla}) {
    final id = _hash(blob);
    final ahora = DateTime.now();
    _vistos.removeWhere((_, t) => ahora.difference(t) > _ventanaDedupe);
    if (_vistos.containsKey(id)) {
      duplicados++;
      return; // ya llegó por el otro camino
    }
    _vistos[id] = ahora;
    while (_vistos.length > _maxVistos) {
      _vistos.remove(_vistos.keys.first);
    }

    if (deMalla) {
      porMalla++;
    } else {
      porAncla++;
    }
    if (!_incomingCtrl.isClosed) _incomingCtrl.add(blob);
  }

  /// Envía por los dos caminos a la vez. El receptor deduplica.
  /// Un fallo del ancla nunca impide el envío por la malla.
  @override
  Future<void> send(String encryptedBlob, {bool reliable = false}) async {
    // La malla primero y con su resultado propagado: si falla, el
    // GroupController debe enterarse (para encolar el mensaje).
    final envioMalla = _enviarMalla(encryptedBlob, reliable);

    // El ancla en paralelo, con los errores absorbidos.
    unawaited(() async {
      try {
        await anchor.send(encryptedBlob, reliable: reliable);
      } catch (e) {
        debugPrint('MeshPlusAnchor: el ancla falló al enviar: $e');
      }
    }());

    await envioMalla;
  }

  Future<void> _enviarMalla(String blob, bool reliable) {
    // Llamada tolerante: si la implementación de la malla no acepta el
    // parámetro `reliable`, esta línea igual compila porque es un named
    // opcional en la interfaz.
    return mesh.send(blob, reliable: reliable);
  }

  @override
  Future<void> stop() async {
    await _meshIn?.cancel();
    await _anchorIn?.cancel();
    await _meshState?.cancel();
    _meshIn = _anchorIn = _meshState = null;
    _vistos.clear();
    try {
      await anchor.stop();
    } catch (_) {}
    await mesh.stop();
  }

  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// Datos para la consola de diagnóstico.
  Map<String, dynamic> get compositeStats => {
        'estadoMalla': mesh.currentState.name,
        'hayAncla': anchor.hayAncla,
        'recibidosPorMalla': porMalla,
        'recibidosPorAncla': porAncla,
        'duplicadosDescartados': duplicados,
        ...anchor.anchorStats,
      };
}
