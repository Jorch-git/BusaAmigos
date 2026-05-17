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

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.fromSelf = false,
    this.delivered = false,
  });

  ChatMessage copyWith({bool? delivered}) => ChatMessage(
        id: id,
        senderId: senderId,
        senderName: senderName,
        text: text,
        sentAt: sentAt,
        fromSelf: fromSelf,
        delivered: delivered ?? this.delivered,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sid': senderId,
        'sname': senderName,
        'text': text,
        'ts': sentAt.toUtc().toIso8601String(),
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
      );
}

/// Plantillas rápidas (los chips del fondo del chat en el video).
const List<String> kQuickMessages = [
  '📍 ¿Dónde están?',
  '🏃 Voy para allá',
  '⏳ Espérenme',
  '🟢 Los encontré',
];
