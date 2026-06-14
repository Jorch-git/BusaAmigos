/// Un mensaje del chat de grupo.
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;

  /// `true` cuando el mensaje fue enviado por el usuario local.
  final bool fromSelf;

  /// `true` si el servidor/peers ya confirmaron recepción. Se usa para los
  /// checks tipo whatsapp del video (✓ / ✓✓).
  final bool delivered;

  /// ---- Respuesta / cita (estilo WhatsApp) ----
  /// Si este mensaje es una respuesta a otro, aquí va el id del mensaje
  /// citado. `null` si no es respuesta.
  final String? replyToId;

  /// Copia del texto del mensaje citado (snapshot). Guardamos una copia para
  /// no depender de que el mensaje original siga en memoria, y para poder
  /// pintar la cita aunque el original se haya perdido en la red.
  final String? replyToText;

  /// Nombre del autor del mensaje citado.
  final String? replyToSender;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.fromSelf = false,
    this.delivered = false,
    this.replyToId,
    this.replyToText,
    this.replyToSender,
  });

  bool get isReply => replyToId != null;

  ChatMessage copyWith({bool? delivered}) => ChatMessage(
        id: id,
        senderId: senderId,
        senderName: senderName,
        text: text,
        sentAt: sentAt,
        fromSelf: fromSelf,
        delivered: delivered ?? this.delivered,
        replyToId: replyToId,
        replyToText: replyToText,
        replyToSender: replyToSender,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sid': senderId,
        'sname': senderName,
        'text': text,
        'ts': sentAt.toUtc().toIso8601String(),
        if (replyToId != null) 'rid': replyToId,
        if (replyToText != null) 'rtext': replyToText,
        if (replyToSender != null) 'rsender': replyToSender,
      };

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    required String selfId,
  }) =>
      ChatMessage(
        id: json['id'] as String,
        senderId: json['sid'] as String,
        senderName: json['sname'] as String,
        text: json['text'] as String,
        sentAt: DateTime.parse(json['ts'] as String),
        fromSelf: json['sid'] == selfId,
        delivered: true,
        replyToId: json['rid'] as String?,
        replyToText: json['rtext'] as String?,
        replyToSender: json['rsender'] as String?,
      );
}

/// Plantillas rápidas (los chips del fondo del chat en el video).
const List<String> kQuickMessages = [
  '📍 ¿Dónde están?',
  '🏃 Voy para allá',
  '⏳ Espérenme',
  '🟢 Los encontré',
];
