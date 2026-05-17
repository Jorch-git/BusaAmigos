import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/position.dart';
import '../models/sos_alert.dart';
import 'crypto/group_code.dart';
import 'crypto/group_crypto.dart';
import 'location/location_service.dart';
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

  GroupController({
    required this.location,
    required this.transport,
  });

  // ---- Estado público ----

  Group? _group;
  Group? get group => _group;

  GroupCrypto? _crypto;
  GroupCrypto? get crypto => _crypto;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

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
    );
  }

  Future<Group> _bootstrap({
    required String code,
    required String groupName,
    required String myDisplayName,
    required bool requireVerification,
  }) async {
    _selfId = _uuid.v4();
    _crypto = await GroupCrypto.deriveFromCode(code);

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

    await location.start();
    await transport.start(groupCode: code, selfId: _selfId!);

    await Future.delayed(const Duration(seconds: 2));

    _stateSub = transport.stateStream.listen((s) {
      debugPrint('GroupController: Estado del transporte cambió a: $s');
      _transportState = s;

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

    _headingSub = location.headingStream.listen((h) {
      _selfHeading = h;
      notifyListeners();
    });

    await Future.delayed(const Duration(milliseconds: 500));
    await _send(_buildSelfHello());
    debugPrint('GroupController: Hello inicial enviado');

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final pos = location.lastPosition;
      if (pos != null) {
        _send(PositionMessage(_selfId!, pos));
      } else {
        // Sin GPS aún: mandamos un Hello "vacío" como heartbeat para que
        // los demás vean que seguimos online aunque no podamos pintarnos.
        _send(_buildSelfHello());
      }
    });

    _helloTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send(_buildSelfHello());
    });

    _staleCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // Refresco la UI para que recalcule status (online/stale/offline) según
      // la edad de lastSeenAt.
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

    notifyListeners();
    return _group!;
  }

  /// Construye el Hello del miembro local INCLUYENDO su última posición
  /// conocida. Esto es importante: si solo enviáramos id+nombre, los
  /// receptores nos verían como "sin GPS" hasta el primer PositionMessage.
  HelloMessage _buildSelfHello() {
    final selfMember = _group?.self;
    if (selfMember == null) {
      // Caso muy temprano: aún no hay grupo. No debería pasar pero por las dudas.
      return HelloMessage(Member(
        id: _selfId ?? '',
        displayName: '',
        colorSeed: 0,
      ));
    }
    // Refrescamos lastPosition con la más reciente del LocationService.
    final freshPos = location.lastPosition ?? selfMember.lastPosition;
    final m = selfMember.copyWith(lastPosition: freshPos);
    return HelloMessage(m);
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
    _incomingSub = _stateSub = _posSub = _headingSub = null;
    _heartbeatTimer = _staleCheckTimer = _helloTimer = null;
    _verificationTimer = _outboxTimer = null;

    await transport.stop();
    await location.stop();

    _group = null;
    _crypto = null;
    _messages.clear();
    _activeSos = null;
    _selfId = null;
    _verificationState = GroupVerificationState.notRequired;
    _outbox.clear();
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

  Future<void> sendChat(String text) async {
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

    final crypto = _crypto;
    if (crypto == null) return;

    final payload = await crypto.decryptJson(blob);
    if (payload == null) return;

    final TransportMessage msg;
    try {
      msg = TransportMessage.fromJson(payload);
    } catch (e) {
      debugPrint('GroupController: payload no parseable: $e');
      return;
    }

    // CUALQUIER mensaje válido del miembro lo "toca" (= lo marca como visto
    // ahora). Esto es lo que hace que un peer aparezca como online en cuanto
    // chatea, aunque no haya mandado posición todavía.
    late final String sourceMemberId;
    switch (msg) {
      case HelloMessage():       sourceMemberId = msg.member.id;
      case PositionMessage():    sourceMemberId = msg.memberId;
      case ChatMessageEnvelope(): sourceMemberId = msg.message.senderId;
      case SosMessage():         sourceMemberId = msg.alert.triggeredBy;
      case SosResponseMessage(): sourceMemberId = msg.memberId;
      case LeaveMessage():       sourceMemberId = msg.memberId;
    }
    if (sourceMemberId != _selfId) {
      _touchMember(sourceMemberId);
    }

    switch (msg) {
      case HelloMessage():
        _onMemberHello(msg.member);
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

  /// Marca a un miembro existente como "visto ahora". Si no existe lo crea
  /// como Desconocido (su Hello debería llegar después y rellenar el nombre).
  void _touchMember(String memberId) {
    if (_group == null) return;
    final existing = _group!.members.where((m) => m.id == memberId).firstOrNull;
    if (existing != null) {
      _group = _group!.withMember(existing.touched());
    } else {
      // Nuevo miembro detectado por mensaje no-Hello: lo creamos con
      // marcador "Desconocido" hasta que llegue su Hello.
      _group = _group!.withMember(Member(
        id: memberId,
        displayName: 'Desconocido',
        colorSeed: _colorSeedFor(memberId),
        lastSeenAt: DateTime.now(),
      ));
    }

    // Verificación física: cualquier mensaje válido es prueba de proximidad.
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
    final self = _group!.self;
    if (self == null) return;
    _group = _group!.withMember(self.copyWith(
      lastPosition: pos,
      lastSeenAt: DateTime.now(),
    ));
    notifyListeners();
  }

  /// Procesa un Hello entrante. CRÍTICO: si el Hello viene SIN posición pero
  /// nosotros ya teníamos una posición previa para ese miembro, NO la pisamos.
  void _onMemberHello(Member m) {
    if (_group == null || m.id == _selfId) return;

    // ¿Ya conocíamos a este miembro?
    final existing = _group!.members.where((x) => x.id == m.id).firstOrNull;

    final Member merged;
    if (existing == null) {
      // Nuevo miembro. Lo agregamos con su posición (si la trae) y lastSeenAt=now.
      merged = m.copyWith(
        isSelf: false,
        lastSeenAt: DateTime.now(),
      );
    } else {
      // Miembro conocido. Actualizamos nombre/colorSeed por si cambió,
      // PRESERVAMOS la posición existente si el Hello no trae una nueva,
      // y marcamos visto.
      merged = existing.copyWith(
        displayName: m.displayName,
        // Si el Hello trae posición, usamos esa; si no, conservamos la previa.
        lastPosition: m.lastPosition ?? existing.lastPosition,
        lastSeenAt: DateTime.now(),
      );
    }

    _group = _group!.withMember(merged);
    debugPrint('GroupController: Hello procesado: ${merged.displayName} (pos=${merged.lastPosition?.hasGps == true})');

    notifyListeners();

    // Le contestamos con NUESTRO hello (con nuestra posición actual) para
    // que él también nos vea con coordenadas, no solo como id.
    _send(_buildSelfHello());
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
    notifyListeners();
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
    final crypto = _crypto;
    if (crypto == null) return;

    try {
      final blob = await crypto.encryptJson(msg.toJson());

      if (persistent && _transportState != TransportState.connected) {
        _outbox.add(_PendingMessage(blob, DateTime.now(), msg.runtimeType.toString()));
        notifyListeners();
        return;
      }

      await transport.send(blob);
    } catch (e) {
      debugPrint('GroupController: error enviando ${msg.runtimeType}: $e');
      if (persistent) {
        try {
          final blob = await crypto.encryptJson(msg.toJson());
          _outbox.add(_PendingMessage(blob, DateTime.now(), msg.runtimeType.toString()));
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

  double _quickDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final x = (lng2 - lng1) * 3.14159 / 180 * (earthRadius * 0.9986);
    final y = (lat2 - lat1) * 3.14159 / 180 * earthRadius;
    return (x * x + y * y).abs();
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
