import 'member.dart';

/// Un grupo activo. Cada celular puede tener muchos grupos guardados pero
/// uno solo "activo" a la vez (el que se está usando en el radar).
///
/// Ojo: la `groupKey` (clave de cifrado de 32 bytes derivada del [code])
/// no se serializa nunca a disco — siempre se rederiva del code para no
/// guardar material criptográfico en almacenamiento. Ver [GroupCrypto].
class Group {
  /// ID interno del grupo (UUID). Distinto del [code] visible al usuario.
  final String id;

  /// Nombre que ve el usuario, ej. "Festival 2026".
  final String name;

  /// Código corto compartible (ej. `FMO-482KL3`). De aquí se deriva la clave.
  final String code;

  /// Lista de miembros conocidos. Incluye al `self`.
  final List<Member> members;

  /// Cuándo se creó/se unió.
  final DateTime createdAt;

  const Group({
    required this.id,
    required this.name,
    required this.code,
    required this.members,
    required this.createdAt,
  });

  Member? get self {
    for (final m in members) {
      if (m.isSelf) return m;
    }
    return null;
  }

  List<Member> get others => members.where((m) => !m.isSelf).toList();

  int get connectedCount => members
      .where((m) => m.status == MemberStatus.online)
      .length;

  Group copyWith({
    String? name,
    List<Member>? members,
  }) {
    return Group(
      id: id,
      name: name ?? this.name,
      code: code,
      members: members ?? this.members,
      createdAt: createdAt,
    );
  }

  /// Reemplaza un miembro por id, o lo agrega si no existía.
  Group withMember(Member updated) {
    final idx = members.indexWhere((m) => m.id == updated.id);
    final next = [...members];
    if (idx == -1) {
      next.add(updated);
    } else {
      next[idx] = updated;
    }
    return copyWith(members: next);
  }

  Group withoutMember(String memberId) {
    return copyWith(
      members: members.where((m) => m.id != memberId).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'members': members.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory Group.fromJson(Map<String, dynamic> json, {String? selfId}) {
    final membersJson = (json['members'] as List).cast<Map<String, dynamic>>();
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      members: membersJson
          .map((m) => Member.fromJson(m, isSelf: m['id'] == selfId))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
