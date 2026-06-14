import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/position.dart';
import '../models/sos_alert.dart';
import 'crypto/group_code.dart';
import 'crypto/group_crypto.dart';
import 'group_storage.dart';
import 'location/location_service.dart';
import 'logging/event_log_service.dart';
import 'notifications/notification_service.dart';
import 'notifications/foreground_service.dart';
import 'sensors/beacon_config.dart';
import 'sensors/sensor_fusion_service.dart';
import 'transport/codec/payload_codec.dart';
import 'transport/transport_message.dart';
import 'transport/transport_service.dart';

/// Estado de la verificación física al unirse a un grupo.
enum GroupVerificationState {
  notRequired,
  pending,
  confirmed,
  timedOut,
}

class GroupController extends ChangeNotifier {
  final LocationService location;
  final TransportService transport;
  final GroupStorage storage;
  final SensorFusionService sensors;
  final EventLogService eventLog;

  /// Config del beacon/sensores. Mutable: se puede ajustar en caliente desde
  /// la Consola/Settings con [updateConfig].
  BeaconConfig config;

  GroupController({
    required this.location,
    required this.transport,
    required this.storage,
    required this.sensors,
    required this.eventLog,
    this.config = const BeaconConfig(),
  });

  SavedGroup? savedGroup;

  // ---- Estado público ----

  Group? _group;
  Group? get group => _group;

  GroupCrypto? _crypto;
  GroupCrypto? get crypto => _crypto;

  PayloadCodec? _codec;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Cantidad de mensajes no leídos (para el badge en la pestaña Chat).
  /// Se incrementa al recibir un mensaje ajeno mientras el chat NO está
  /// abierto, y se resetea con [markChatRead].
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  /// `true` cuando el usuario está viendo la pestaña de Chat. Si está abierto,
  /// los mensajes entrantes NO incrementan el badge ni disparan notificación.
  bool _chatOpen = false;
  bool get chatOpen => _chatOpen;

  SosAlert? _activeSos;
  SosAlert? get activeSos => _activeSos;

  TransportState _transportState = TransportState.idle;
  TransportState get transportState => _transportState;

  double? _selfHeading;
  double? get selfHeading => _selfHeading;

  GroupVerificationState _verificationState = GroupVerificationState.notRequired;
  GroupVerificationState get verificationState => _verificationState;

  final _sosIncomingCtrl = StreamController<SosAlert>.broadcast();
  Stream<SosAlert> get sosIncomingStream => _sosIncomingCtrl.stream;

  // ---- Internals ----

  StreamSubscription? _incomingSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _headingSub;
  StreamSubscription? _motionSub;
  Timer? _heartbeatTimer;
  Timer? _staleCheckTimer;
  Timer? _helloTimer;
  Timer? _verificationTimer;
  Timer? _outboxTimer;

  String? _selfId;
  static const _uuid = Uuid();

  final List<_PendingMessage> _outbox = [];
  int get pendingMessagesCount => _outbox.length;

  Future<Group> createGroup({
    required String groupName,
    required String myDisplayName,
  }) async {
    final code = GroupCode.generate();
    return _bootstrap(
      code: code,
      groupName: groupName,
      myDisplayName: myDisplayName,
      requireVerification: false,
      wasHost: true,
    );
  }

  Future<Group> joinGroup({
    required String code,
    required String myDisplayName,
    bool requireVerification = true,
  }) async {
    if (!GroupCode.isValid(code)) {
      throw ArgumentError('Código inválido');
    }
    return _bootstrap(
      code: GroupCode.normalize(code),
      groupName: 'Grupo',
      myDisplayName: myDisplayName,
      requireVerification: requireVerification,
      wasHost: false,
    );
  }

  Future<Group> restoreSavedGroup({bool requireVerification = false}) async {
    final saved = savedGroup ?? await storage.load();
    if (saved == null) {
      throw StateError('No hay grupo guardado para restaurar');
    }
    return _bootstrap(
      code: saved.groupCode,
      groupName: saved.groupName,
      myDisplayName: saved.displayName,
      requireVerification: requireVerification,
      selfId: saved.selfId,
      wasHost: saved.wasHost,
    );
  }

  Future<void> loadSavedGroup() async {
    savedGroup = await storage.load();
    notifyListeners();
  }

  /// Ajusta la configuración del beacon/sensores en caliente.
  void updateConfig(BeaconConfig newConfig) {
    config = newConfig;
    sensors.config = newConfig;
    // Reprograma el beacon con el nuevo intervalo.
    if (_heartbeatTimer != null) {
      _heartbeatTimer!.cancel();
      _heartbeatTimer = Timer.periodic(config.beaconInterval, (_) => _beacon());
    }
    eventLog.logSystem('Config actualizada', extra: newConfig.toJson());
    notifyListeners();
  }

  Future<Group> _bootstrap({
    required String code,
    required String groupName,
    required String myDisplayName,
    required bool requireVerification,
    required bool wasHost,
    String? selfId,
  }) async {
    _selfId = selfId ?? _uuid.v4();
    _crypto = await GroupCrypto.deriveFromCode(code);
    _codec = PayloadCodec(_crypto!);

    final self = Member(
      id: _selfId!,
      displayName: myDisplayName,
      colorSeed: _colorSeedFor(_selfId!),
      isSelf: true,
      lastPosition: location.lastPosition,
      lastSeenAt: DateTime.now(),
    );

    _group = Group(
      id: _uuid.v4(),
      name: groupName,
      code: code,
      members: [self],
      createdAt: DateTime.now(),
    );

    _verificationState = requireVerification
        ? GroupVerificationState.pending
        : GroupVerificationState.notRequired;

    // Arranca GPS + brújula + fusión de sensores.
    await location.start();
    sensors.config = config;
    await sensors.start();
    await transport.start(groupCode: code, selfId: _selfId!);

    eventLog.logSystem('Sesión iniciada', extra: {
      'group': groupName,
      'host': wasHost,
      'beaconMs': config.beaconInterval.inMilliseconds,
    });

    // Foreground service: mantiene la app viva en segundo plano para seguir
    // recibiendo mensajes/SOS con la pantalla apagada.
    await ForegroundKeepAlive.instance.start(
      groupName: groupName,
      memberCount: _group?.others.length ?? 0,
    );

    await Future.delayed(const Duration(seconds: 2));

    _stateSub = transport.stateStream.listen((s) {
      debugPrint('GroupController: Estado del transporte cambió a: $s');
      _transportState = s;
      eventLog.logSystem('Transporte: ${s.name}');

      if (s == TransportState.connected && _group?.self != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _send(_buildSelfHello());
        });
        _flushOutbox();
      }

      notifyListeners();
    });

    _incomingSub = transport.incomingStream.listen(_handleIncoming);

    _posSub = location.positionStream.listen((pos) {
      _onSelfPositionChanged(pos);
    });

    // El rumbo del SO (FlutterCompass) se inyecta como validación suave en la
    // fusión; el rumbo principal lo calcula SensorFusionService.
    _headingSub = location.headingStream.listen((h) {
      sensors.feedExternalHeading(h, weight: 0.05);
    });

    // El snapshot de movimiento refresca la flecha/radar y el "self heading".
    _motionSub = sensors.snapshotStream.listen((snap) {
      _selfHeading = snap.headingDeg;
      notifyListeners();
    });

    await Future.delayed(const Duration(milliseconds: 500));
    await _send(_buildSelfHello());
    debugPrint('GroupController: Hello inicial enviado');

    // Beacon: emite posición fusionada al ritmo configurado (1 s por defecto).
    _heartbeatTimer = Timer.periodic(config.beaconInterval, (_) => _beacon());

    _helloTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send(_buildSelfHello());
    });

    _staleCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      notifyListeners();
    });

    _outboxTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _flushOutbox();
    });

    if (requireVerification) {
      _verificationTimer = Timer(const Duration(seconds: 60), () {
        if (_verificationState == GroupVerificationState.pending) {
          _verificationState = GroupVerificationState.timedOut;
          notifyListeners();
        }
      });
    }

    await _saveLastGroup(wasHost: wasHost);
    notifyListeners();
    return _group!;
  }

  /// Un "tick" del beacon: construye la posición fusionada (GPS + sensores,
  /// con dead reckoning si el GPS está viejo) y la difunde.
  void _beacon() {
    final pos = _fusedSelfPosition();
    if (pos != null) {
      _onSelfPositionChanged(pos);
      if (_selfId != null) _send(PositionMessage(_selfId!, pos));
    } else {
      _send(_buildSelfHello());
    }
  }

  /// Combina el último GPS con el snapshot de la fusión de sensores. Si el GPS
  /// está fresco, lo usa tal cual (más rumbo/movimiento). Si está viejo,
  /// propaga la posición por dead reckoning. Si no hay GPS, devuelve solo
  /// movimiento (o null si includeMotion está apagado).
  Position? _fusedSelfPosition() {
    final snap = sensors.lastSnapshot;
    final gps = location.lastPosition;

    Position withMotion(Position p, {bool dr = false}) => p.copyWith(
          heading: snap.headingDeg,
          headingConfidence: snap.headingConfidence,
          tilt: snap.tiltDeg,
          steps: snap.stepCount,
          cadence: snap.cadence,
          motion: snap.motion.name,
          deadReckoned: dr,
          timestamp: DateTime.now(),
        );

    if (gps != null && gps.hasGps) {
      final freshGps = DateTime.now().difference(gps.timestamp).inSeconds < 8;
      if (freshGps) return withMotion(gps);

      // GPS viejo -> propaga por dead reckoning desde el último fix.
      const mPerDegLat = 111320.0;
      final dLat = snap.drNorth / mPerDegLat;
      final dLng = snap.drEast /
          (mPerDegLat * math.cos(gps.latitude! * math.pi / 180));
      return withMotion(
        gps.copyWith(
          latitude: gps.latitude! + dLat,
          longitude: gps.longitude! + dLng,
        ),
        dr: true,
      );
    }

    // Sin GPS: al menos compartimos rumbo/movimiento (sirve para la flecha).
    if (config.includeMotion) {
      return withMotion(Position(timestamp: DateTime.now()));
    }
    return null;
  }

  /// Construye el Hello del miembro local incluyendo su última posición.
  /// v8: incluye también el nombre del grupo, para que quien se una adopte
  /// el nombre real en vez de quedarse con "Grupo".
  HelloMessage _buildSelfHello() {
    final selfMember = _group?.self;
    if (selfMember == null) {
      return HelloMessage(Member(
        id: _selfId ?? '',
        displayName: '',
        colorSeed: 0,
      ));
    }
    final freshPos =
        _fusedSelfPosition() ?? location.lastPosition ?? selfMember.lastPosition;
    final m = selfMember.copyWith(lastPosition: freshPos);
    return HelloMessage(m, groupName: _group?.name);
  }

  Future<void> leaveGroup() async {
    if (_selfId != null) {
      await _send(LeaveMessage(_selfId!));
    }
    _heartbeatTimer?.cancel();
    _staleCheckTimer?.cancel();
    _helloTimer?.cancel();
    _verificationTimer?.cancel();
    _outboxTimer?.cancel();
    await _incomingSub?.cancel();
    await _stateSub?.cancel();
    await _posSub?.cancel();
    await _headingSub?.cancel();
    await _motionSub?.cancel();
    _incomingSub = _stateSub = _posSub = _headingSub = _motionSub = null;
    _heartbeatTimer = _staleCheckTimer = _helloTimer = null;
    _verificationTimer = _outboxTimer = null;

    await transport.stop();
    await location.stop();
    await sensors.stop();
    await ForegroundKeepAlive.instance.stop();

    eventLog.logSystem('Sesión finalizada');

    _group = null;
    _crypto = null;
    _codec = null;
    _messages.clear();
    _activeSos = null;
    _selfId = null;
    _unreadCount = 0;
    _chatOpen = false;
    _verificationState = GroupVerificationState.notRequired;
    _outbox.clear();
    savedGroup = null;
    await storage.clear();
    notifyListeners();
  }

  void acceptUnverifiedGroup() {
    if (_verificationState == GroupVerificationState.timedOut) {
      _verificationState = GroupVerificationState.notRequired;
      notifyListeners();
    }
  }

  Future<void> resendHello() async {
    await _send(_buildSelfHello());
  }

  Future<void> sendChat(String text, {ChatMessage? replyTo}) async {
    if (_group == null || _selfId == null) return;
    final self = _group!.self!;
    final msg = ChatMessage(
      id: _uuid.v4(),
      senderId: _selfId!,
      senderName: self.displayName,
      text: text,
      sentAt: DateTime.now(),
      fromSelf: true,
      delivered: false,
      replyToId: replyTo?.id,
      replyToText: replyTo?.text,
      replyToSender: replyTo?.senderName,
    );
    _messages.add(msg);
    notifyListeners();
    await _send(ChatMessageEnvelope(msg), persistent: true);
  }

  Future<void> triggerSos() async {
    if (_group == null || _selfId == null) return;
    final self = _group!.self!;
    final alert = SosAlert(
      triggeredBy: _selfId!,
      triggeredByName: self.displayName,
      triggeredAt: DateTime.now(),
    );
    _activeSos = alert;
    notifyListeners();
    await _send(SosMessage(alert), persistent: true);
  }

  Future<void> respondToSos(SosResponse response) async {
    final alert = _activeSos;
    if (alert == null || _selfId == null || _group == null) return;

    double? distance;
    final triggerer = _group!.members.firstWhere(
      (m) => m.id == alert.triggeredBy,
      orElse: () => _group!.self!,
    );
    final selfPos = _group!.self?.lastPosition;
    final triggererPos = triggerer.lastPosition;
    if (selfPos != null && triggererPos != null && selfPos.hasGps && triggererPos.hasGps) {
      distance = _quickDistance(
        selfPos.latitude!, selfPos.longitude!,
        triggererPos.latitude!, triggererPos.longitude!,
      );
    }

    _activeSos = alert.withResponse(_selfId!, response, distance: distance);
    notifyListeners();

    await _send(
      SosResponseMessage(
        memberId: _selfId!,
        response: response,
        distance: distance,
      ),
      persistent: true,
    );
  }

  Future<void> dismissSos() async {
    _activeSos = null;
    notifyListeners();
  }

  // ---- Manejo de entrada ----

  Future<void> _handleIncoming(String blob) async {
    if (blob.startsWith('__GHOST__:')) {
      _handleGhost(blob.substring('__GHOST__:'.length));
      return;
    }

    final codec = _codec;
    if (codec == null) return;

    final payload = await codec.decode(blob);
    if (payload == null) return;

    final TransportMessage msg;
    try {
      msg = TransportMessage.fromJson(payload);
    } catch (e) {
      debugPrint('GroupController: payload no parseable: $e');
      return;
    }

    late final String sourceMemberId;
    switch (msg) {
      case HelloMessage():        sourceMemberId = msg.member.id;
      case PositionMessage():     sourceMemberId = msg.memberId;
      case ChatMessageEnvelope(): sourceMemberId = msg.message.senderId;
      case SosMessage():          sourceMemberId = msg.alert.triggeredBy;
      case SosResponseMessage():  sourceMemberId = msg.memberId;
      case LeaveMessage():        sourceMemberId = msg.memberId;
    }

    // Log del evento entrante (ya descifrado y descomprimido = legible).
    final senderName = _group?.members
        .where((m) => m.id == sourceMemberId)
        .firstOrNull
        ?.displayName;
    eventLog.logReceived(
      type: payload['type'] as String? ?? 'unknown',
      payload: payload,
      memberId: sourceMemberId,
      memberName: senderName,
      wireBytes: blob.length,
      transport: transport.runtimeType.toString(),
    );

    if (sourceMemberId != _selfId) {
      _touchMember(sourceMemberId);
    }

    switch (msg) {
      case HelloMessage():
        _onMemberHello(msg.member, msg.groupName);
      case PositionMessage():
        _onMemberPosition(msg.memberId, msg.position);
      case ChatMessageEnvelope():
        _onChatMessage(msg.message);
      case SosMessage():
        _onSosTriggered(msg.alert);
      case SosResponseMessage():
        _onSosResponse(msg);
      case LeaveMessage():
        _onMemberLeave(msg.memberId);
    }
  }

  void _touchMember(String memberId) {
    if (_group == null) return;
    final existing = _group!.members.where((m) => m.id == memberId).firstOrNull;
    if (existing != null) {
      _group = _group!.withMember(existing.touched());
    } else {
      _group = _group!.withMember(Member(
        id: memberId,
        displayName: 'Desconocido',
        colorSeed: _colorSeedFor(memberId),
        lastSeenAt: DateTime.now(),
      ));
    }

    if (_verificationState == GroupVerificationState.pending) {
      _verificationState = GroupVerificationState.confirmed;
      _verificationTimer?.cancel();
    }
  }

  void _handleGhost(String b64) {
    try {
      final data = jsonDecode(utf8.decode(base64Url.decode(b64))) as Map<String, dynamic>;
      final id = data['id'] as String;
      final name = data['name'] as String;
      final colorSeed = data['colorSeed'] as int;
      final lat = (data['lat'] as num).toDouble();
      final lng = (data['lng'] as num).toDouble();

      final pos = Position(
        latitude: lat,
        longitude: lng,
        accuracy: 5,
        timestamp: DateTime.parse(data['ts'] as String),
      );

      final existing = _group?.members.any((m) => m.id == id) ?? false;
      if (!existing && _group != null) {
        _group = _group!.withMember(Member(
          id: id,
          displayName: name,
          colorSeed: colorSeed,
          lastPosition: pos,
          lastSeenAt: DateTime.now(),
        ));
      } else if (_group != null) {
        final m = _group!.members.firstWhere((x) => x.id == id);
        _group = _group!.withMember(m.copyWith(
          lastPosition: pos,
          lastSeenAt: DateTime.now(),
        ));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('GroupController: ghost malformado: $e');
    }
  }

  void _onSelfPositionChanged(Position pos) {
    if (_group == null) return;

    // Anclaje del dead reckoning cuando llega un GPS confiable.
    if (pos.hasGps && (pos.accuracy ?? 999) <= config.gpsAnchorAccuracy && !pos.deadReckoned) {
      sensors.anchorToGps();
    }

    final self = _group!.self;
    if (self == null) return;
    _group = _group!.withMember(self.copyWith(
      lastPosition: pos,
      lastSeenAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void _onMemberHello(Member m, [String? groupName]) {
    if (_group == null || m.id == _selfId) return;

    // Adoptar el nombre real del grupo si el nuestro es el default "Grupo"
    // y el anfitrión nos mandó uno. Esto corrige el bug de que quien se une
    // veía "Grupo" en vez del nombre que puso el creador.
    if (groupName != null &&
        groupName.isNotEmpty &&
        (_group!.name == 'Grupo' || _group!.name.isEmpty) &&
        groupName != 'Grupo') {
      _group = _group!.copyWith(name: groupName);
      _persistGroupName();
    }

    final existing = _group!.members.where((x) => x.id == m.id).firstOrNull;

    final Member merged;
    if (existing == null) {
      merged = m.copyWith(
        isSelf: false,
        lastSeenAt: DateTime.now(),
      );
    } else {
      merged = existing.copyWith(
        displayName: m.displayName,
        lastPosition: m.lastPosition ?? existing.lastPosition,
        lastSeenAt: DateTime.now(),
      );
    }

    _group = _group!.withMember(merged);
    debugPrint('GroupController: Hello procesado: ${merged.displayName} (pos=${merged.lastPosition?.hasGps == true})');

    notifyListeners();

    _send(_buildSelfHello());
  }

  /// Actualiza el nombre del grupo en almacenamiento (tras adoptarlo del host).
  Future<void> _persistGroupName() async {
    final saved = savedGroup;
    if (saved == null || _group == null) return;
    final updated = SavedGroup(
      groupCode: saved.groupCode,
      groupName: _group!.name,
      displayName: saved.displayName,
      selfId: saved.selfId,
      wasHost: saved.wasHost,
    );
    savedGroup = updated;
    try {
      await storage.save(updated);
    } catch (_) {}
  }

  void _onMemberPosition(String memberId, Position pos) {
    if (_group == null || memberId == _selfId) return;
    final existing = _group!.members.where((m) => m.id == memberId).firstOrNull;
    final base = existing ??
        Member(
          id: memberId,
          displayName: 'Desconocido',
          colorSeed: _colorSeedFor(memberId),
        );
    _group = _group!.withMember(base.copyWith(
      lastPosition: pos,
      lastSeenAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void _onChatMessage(ChatMessage msg) {
    if (_messages.any((m) => m.id == msg.id)) return;
    _messages.add(msg);
    _messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));

    // Si el mensaje es de otro y el chat NO está abierto, incrementamos el
    // badge de no leídos y disparamos notificación pop.
    if (!msg.fromSelf && !_chatOpen) {
      _unreadCount++;
      NotificationService.instance.showMessage(
        senderName: msg.senderName,
        text: msg.text,
      );
    }

    notifyListeners();
  }

  /// Marca el chat como abierto/cerrado. Cuando se abre, resetea no leídos.
  void setChatOpen(bool open) {
    _chatOpen = open;
    if (open) {
      _unreadCount = 0;
      NotificationService.instance.clearMessages();
    }
    notifyListeners();
  }

  /// Resetea el contador de no leídos sin cambiar el estado de chat abierto.
  void markChatRead() {
    if (_unreadCount != 0) {
      _unreadCount = 0;
      notifyListeners();
    }
  }

  void _onSosTriggered(SosAlert alert) {
    final existing = _activeSos;
    if (existing != null &&
        existing.triggeredBy == alert.triggeredBy &&
        existing.triggeredAt.difference(alert.triggeredAt).abs() <
            const Duration(seconds: 30)) {
      return;
    }
    _activeSos = alert;
    notifyListeners();
    // Notificación pop de máxima prioridad (a menos que sea nuestro propio SOS).
    if (alert.triggeredBy != _selfId) {
      NotificationService.instance.showSos(
        triggeredByName: alert.triggeredByName,
      );
    }
    if (!_sosIncomingCtrl.isClosed) {
      _sosIncomingCtrl.add(alert);
    }
  }

  void _onSosResponse(SosResponseMessage msg) {
    if (_activeSos == null) return;
    _activeSos = _activeSos!.withResponse(
      msg.memberId,
      msg.response,
      distance: msg.distance,
    );
    notifyListeners();
  }

  void _onMemberLeave(String memberId) {
    if (_group == null) return;
    _group = _group!.withoutMember(memberId);
    notifyListeners();
  }

  // ---- Cola de reenvío ----

  Future<void> _send(TransportMessage msg, {bool persistent = false}) async {
    final codec = _codec;
    if (codec == null) return;

    try {
      final json = msg.toJson();
      final enc = await codec.encode(
        json,
        forceCompress: config.compress ? null : false,
      );

      // Registro del evento saliente con métricas de tamaño/compresión.
      eventLog.logSent(
        type: json['type'] as String? ?? msg.runtimeType.toString(),
        payload: json,
        memberId: _selfId,
        memberName: _group?.self?.displayName,
        rawBytes: enc.rawBytes,
        wireBytes: enc.wireBytes,
        compressed: enc.wasCompressed,
        transport: transport.runtimeType.toString(),
      );

      if (persistent && _transportState != TransportState.connected) {
        _outbox.add(_PendingMessage(enc.blob, DateTime.now(), msg.runtimeType.toString()));
        notifyListeners();
        return;
      }

      await transport.send(enc.blob);
    } catch (e) {
      debugPrint('GroupController: error enviando ${msg.runtimeType}: $e');
      if (persistent) {
        try {
          final enc = await codec.encode(msg.toJson());
          _outbox.add(_PendingMessage(enc.blob, DateTime.now(), msg.runtimeType.toString()));
          notifyListeners();
        } catch (_) {}
      }
    }
  }

  Future<void> _flushOutbox() async {
    if (_outbox.isEmpty) return;
    if (_transportState != TransportState.connected) return;

    final pending = List<_PendingMessage>.from(_outbox);
    final delivered = <_PendingMessage>[];

    for (final p in pending) {
      final isCritical = p.typeName.contains('Sos');
      final maxAge = isCritical ? const Duration(minutes: 30) : const Duration(minutes: 5);
      if (DateTime.now().difference(p.queuedAt) > maxAge) {
        delivered.add(p);
        continue;
      }
      try {
        await transport.send(p.blob);
        delivered.add(p);
      } catch (e) {
        break;
      }
    }

    _outbox.removeWhere((p) => delivered.contains(p));
    if (delivered.isNotEmpty) notifyListeners();
  }

  Future<void> _saveLastGroup({required bool wasHost}) async {
    if (_group == null || _selfId == null) return;
    final saved = SavedGroup(
      groupCode: _group!.code,
      groupName: _group!.name,
      displayName: _group!.self?.displayName ?? '',
      selfId: _selfId!,
      wasHost: wasHost,
    );
    savedGroup = saved;
    await storage.save(saved);
  }

  int _colorSeedFor(String id) {
    const palette = [
      0xFFEEC42E, 0xFF1DD27D, 0xFFE24B4A,
      0xFF378ADD, 0xFFEF9F27, 0xFFD4537E,
    ];
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  /// Distancia en metros (Haversine simplificada). Corrige el bug previo:
  /// ahora SÍ saca la raíz (antes devolvía metros al cuadrado).
  double _quickDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final x = (lng2 - lng1) * math.pi / 180 * (earthRadius * 0.9986) *
        math.cos((lat1 + lat2) / 2 * math.pi / 180);
    final y = (lat2 - lat1) * math.pi / 180 * earthRadius;
    return math.sqrt(x * x + y * y);
  }

  @override
  void dispose() {
    _sosIncomingCtrl.close();
    leaveGroup();
    super.dispose();
  }
}

class _PendingMessage {
  final String blob;
  final DateTime queuedAt;
  final String typeName;
  _PendingMessage(this.blob, this.queuedAt, this.typeName);
}
