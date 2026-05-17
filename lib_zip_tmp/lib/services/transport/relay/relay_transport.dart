import 'dart:async';

import '../transport_service.dart';

/// Implementación de transporte vía servidor relay (Firebase, Supabase,
/// backend propio). DEJADO COMO PLACEHOLDER A PROPÓSITO.
///
/// Cuando elijas backend, esta clase se llena así:
///
/// **Si eliges Firebase Firestore:**
/// ```dart
/// final col = FirebaseFirestore.instance
///   .collection('groups').doc(groupCode).collection('messages');
/// _sub = col.orderBy('ts').snapshots().listen((snap) {
///   for (final change in snap.docChanges) {
///     if (change.type == DocumentChangeType.added) {
///       final data = change.doc.data()!;
///       if (data['from'] != selfId) _incomingCtrl.add(data['blob'] as String);
///     }
///   }
/// });
/// ```
///
/// **Si eliges Supabase Realtime:**
/// ```dart
/// _channel = Supabase.instance.client.channel('group:$groupCode')
///   ..onBroadcast(event: 'msg', callback: (payload) {
///     if (payload['from'] != selfId) _incomingCtrl.add(payload['blob']);
///   })
///   ..subscribe();
/// ```
///
/// **Si haces backend propio:** un WebSocket donde el groupCode es el
/// canal y el servidor solo retransmite. Como los blobs vienen cifrados,
/// el servidor no necesita autenticación de contenido.
class RelayTransport implements TransportService {
  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _incomingCtrl = StreamController<String>.broadcast();

  TransportState _state = TransportState.idle;

  @override
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  @override
  Stream<String> get incomingStream => _incomingCtrl.stream;

  @override
  TransportReach get reach => TransportReach.none;

  @override
  Future<void> start({required String groupCode, required String selfId}) async {
    _state = TransportState.error;
    _stateCtrl.add(_state);
    throw UnimplementedError(
      'RelayTransport: agrega tu backend aquí. Mientras tanto, usa '
      'FakeRelayTransport para desarrollo.',
    );
  }

  @override
  Future<void> send(String encryptedBlob) async {
    throw UnimplementedError();
  }

  @override
  Future<void> stop() async {
    _state = TransportState.idle;
    _stateCtrl.add(_state);
  }
}
