import 'position.dart';

/// Estado de conexión visible del miembro.
enum MemberStatus {
  /// Vimos cualquier mensaje suyo (hello, position, chat, sos) hace muy poco.
  online,

  /// Lo vimos hace un rato pero no recientemente. Puede haberse alejado o
  /// entrado a una zona muerta.
  stale,

  /// Hace tanto que no sabemos de él que probablemente se desconectó.
  offline,
}

/// Un miembro del grupo. Cada celular es un miembro: el dueño del
/// dispositivo es identificado como `isSelf == true`.
class Member {
  /// ID estable. Se genera localmente al crear el perfil y se mantiene
  /// entre sesiones. Distinto del nombre.
  final String id;

  /// Nombre que se muestra en la UI. Lo edita el usuario.
  final String displayName;

  /// Color asignado en el radar. Se deriva del id para que sea estable.
  final int colorSeed;

  /// Última posición conocida. `null` mientras aún no hemos recibido GPS suyo.
  /// IMPORTANTE: que este campo sea `null` NO significa que el miembro esté
  /// desconectado — significa que aún no nos ha mandado posición. Para saber
  /// si está online/stale/offline, usar [status], que se basa en [lastSeenAt].
  final Position? lastPosition;

  /// Última vez que recibimos CUALQUIER mensaje de este miembro (hello,
  /// position, chat, sos). Usado para determinar [status] de forma robusta:
  /// un miembro puede estar conectado y mandando chat sin tener GPS aún.
  /// `null` solo en miembros recién creados desde JSON antiguo.
  final DateTime? lastSeenAt;

  /// `true` solo para el miembro local (el dueño del celular).
  final bool isSelf;

  /// Si el miembro disparó un SOS activo.
  final bool sosActive;

  const Member({
    required this.id,
    required this.displayName,
    required this.colorSeed,
    this.lastPosition,
    this.lastSeenAt,
    this.isSelf = false,
    this.sosActive = false,
  });

  /// Estado del miembro basado en cuándo lo vimos por última vez (cualquier
  /// mensaje), NO en si tiene GPS. Un miembro recién unido que aún no envió
  /// posición puede estar perfectamente online.
  MemberStatus get status {
    final seen = lastSeenAt;
    if (seen == null) {
      // Compatibilidad hacia atrás: si no hay lastSeenAt, caemos a la lógica
      // antigua basada en posición.
      final pos = lastPosition;
      if (pos == null) return MemberStatus.offline;
      final secs = pos.age.inSeconds;
      if (secs < 30) return MemberStatus.online;
      if (secs < 120) return MemberStatus.stale;
      return MemberStatus.offline;
    }
    final secs = DateTime.now().difference(seen).inSeconds;
    if (secs < 30) return MemberStatus.online;
    if (secs < 120) return MemberStatus.stale;
    return MemberStatus.offline;
  }

  Member copyWith({
    String? displayName,
    Position? lastPosition,
    DateTime? lastSeenAt,
    bool? sosActive,
    bool? isSelf,
  }) {
    return Member(
      id: id,
      displayName: displayName ?? this.displayName,
      colorSeed: colorSeed,
      lastPosition: lastPosition ?? this.lastPosition,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isSelf: isSelf ?? this.isSelf,
      sosActive: sosActive ?? this.sosActive,
    );
  }

  /// Marca al miembro como visto AHORA. Atajo conveniente para usar en
  /// el controller cada vez que llega cualquier mensaje suyo.
  Member touched() => copyWith(lastSeenAt: DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': displayName,
        'colorSeed': colorSeed,
        if (lastPosition != null) 'pos': lastPosition!.toJson(),
        'sos': sosActive,
      };

  factory Member.fromJson(Map<String, dynamic> json, {bool isSelf = false}) =>
      Member(
        id: json['id'] as String,
        displayName: json['name'] as String,
        colorSeed: json['colorSeed'] as int,
        lastPosition: json['pos'] != null
            ? Position.fromJson(json['pos'] as Map<String, dynamic>)
            : null,
        // lastSeenAt no se serializa: es estado local de "lo acabo de ver".
        // Si lo recibimos por la red, queda null y se setea al tocarlo.
        isSelf: isSelf,
        sosActive: (json['sos'] as bool?) ?? false,
      );
}
