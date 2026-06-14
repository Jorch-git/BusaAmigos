import '../../models/chat_message.dart';
import '../../models/member.dart';
import '../../models/position.dart';
import '../../models/sos_alert.dart';

/// Mensaje en el cable. Todo lo que viaja entre miembros (vía relay o
/// vía P2P) cae en uno de estos tipos. Se serializa a JSON, luego se
/// cifra con [GroupCrypto], y solo el blob cifrado sale del dispositivo.
sealed class TransportMessage {
  const TransportMessage();

  Map<String, dynamic> toJson();

  static TransportMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'hello' => HelloMessage._fromJson(json),
      'pos' => PositionMessage._fromJson(json),
      'chat' => ChatMessageEnvelope._fromJson(json),
      'sos' => SosMessage._fromJson(json),
      'sosResponse' => SosResponseMessage._fromJson(json),
      'leave' => LeaveMessage._fromJson(json),
      _ => throw FormatException('Tipo de mensaje desconocido: $type'),
    };
  }
}

/// Cuando un miembro entra al grupo, anuncia quién es.
///
/// v8: ahora lleva opcionalmente el [groupName]. El anfitrión incluye el
/// nombre real del grupo en su Hello para que los que se unen (que arrancan
/// con "Grupo" por default) adopten el nombre correcto. Ver
/// GroupController._onMemberHello.
class HelloMessage extends TransportMessage {
  final Member member;
  final String? groupName;

  const HelloMessage(this.member, {this.groupName});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'hello',
        'member': member.toJson(),
        if (groupName != null) 'gname': groupName,
      };

  factory HelloMessage._fromJson(Map<String, dynamic> json) => HelloMessage(
        Member.fromJson(json['member'] as Map<String, dynamic>),
        groupName: json['gname'] as String?,
      );
}

/// Anuncio periódico de posición.
class PositionMessage extends TransportMessage {
  final String memberId;
  final Position position;
  const PositionMessage(this.memberId, this.position);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'pos',
        'mid': memberId,
        'pos': position.toJson(),
      };

  factory PositionMessage._fromJson(Map<String, dynamic> json) =>
      PositionMessage(
        json['mid'] as String,
        Position.fromJson(json['pos'] as Map<String, dynamic>),
      );
}

/// Mensaje de chat.
class ChatMessageEnvelope extends TransportMessage {
  final ChatMessage message;
  const ChatMessageEnvelope(this.message);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'chat',
        'msg': message.toJson(),
      };

  factory ChatMessageEnvelope._fromJson(Map<String, dynamic> json) =>
      ChatMessageEnvelope(
        ChatMessage.fromJson(
          json['msg'] as Map<String, dynamic>,
          selfId: '',
        ),
      );
}

/// Disparo de un SOS.
class SosMessage extends TransportMessage {
  final SosAlert alert;
  const SosMessage(this.alert);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'sos',
        'alert': alert.toJson(),
      };

  factory SosMessage._fromJson(Map<String, dynamic> json) =>
      SosMessage(SosAlert.fromJson(json['alert'] as Map<String, dynamic>));
}

/// Respuesta a un SOS de otro miembro.
class SosResponseMessage extends TransportMessage {
  final String memberId;
  final SosResponse response;
  final double? distance;

  const SosResponseMessage({
    required this.memberId,
    required this.response,
    this.distance,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'sosResponse',
        'mid': memberId,
        'r': response.name,
        if (distance != null) 'd': distance,
      };

  factory SosResponseMessage._fromJson(Map<String, dynamic> json) =>
      SosResponseMessage(
        memberId: json['mid'] as String,
        response: SosResponse.values.firstWhere(
          (e) => e.name == json['r'],
          orElse: () => SosResponse.pending,
        ),
        distance: (json['d'] as num?)?.toDouble(),
      );
}

/// Un miembro avisa explícitamente que sale del grupo.
class LeaveMessage extends TransportMessage {
  final String memberId;
  const LeaveMessage(this.memberId);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'leave',
        'mid': memberId,
      };

  factory LeaveMessage._fromJson(Map<String, dynamic> json) =>
      LeaveMessage(json['mid'] as String);
}
