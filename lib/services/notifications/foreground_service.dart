import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Mantiene la app viva en segundo plano mediante un foreground service de
/// Android (notificación persistente). Esto permite que el transporte P2P
/// (Nearby/BLE) y las notificaciones de mensajes/SOS sigan funcionando con
/// la pantalla apagada o la app minimizada.
///
/// LÍMITE HONESTO: esto NO funciona si el usuario mata la app deslizándola
/// de "recientes" o si Android la cierra por falta de memoria extrema. Para
/// ese caso solo un push server (Firebase) puede despertar la app, y eso
/// requeriría backend. El foreground service es lo máximo posible sin servidor.
class ForegroundKeepAlive {
  ForegroundKeepAlive._();
  static final ForegroundKeepAlive instance = ForegroundKeepAlive._();

  bool _running = false;
  bool get isRunning => _running;

  /// Inicializa la config del servicio. Llamar una vez al arrancar la app.
  void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'buscamigos_foreground',
        channelName: 'Buscamigos activo',
        channelDescription:
            'Mantiene la búsqueda de tu grupo activa en segundo plano.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Pide los permisos necesarios (notificaciones + ignorar optimización de
  /// batería para que Android no mate el servicio).
  Future<void> requestPermissions() async {
    final notif = await FlutterForegroundTask.checkNotificationPermission();
    if (notif != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations == false) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  /// Arranca el servicio. La notificación dice que la búsqueda está activa.
  Future<void> start({
    required String groupName,
    required int memberCount,
  }) async {
    if (_running) {
      await updateInfo(groupName: groupName, memberCount: memberCount);
      return;
    }
    try {
      await requestPermissions();
      await FlutterForegroundTask.startService(
        notificationTitle: 'Buscamigos · $groupName',
        notificationText: 'Buscando a $memberCount miembro(s) cerca…',
      );
      _running = true;
      debugPrint('ForegroundKeepAlive: servicio iniciado');
    } catch (e) {
      debugPrint('ForegroundKeepAlive: error iniciando: $e');
    }
  }

  /// Actualiza el texto de la notificación persistente.
  Future<void> updateInfo({
    required String groupName,
    required int memberCount,
  }) async {
    if (!_running) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Buscamigos · $groupName',
        notificationText: 'Buscando a $memberCount miembro(s) cerca…',
      );
    } catch (e) {
      debugPrint('ForegroundKeepAlive: error actualizando: $e');
    }
  }

  /// Detiene el servicio.
  Future<void> stop() async {
    if (!_running) return;
    try {
      await FlutterForegroundTask.stopService();
      _running = false;
      debugPrint('ForegroundKeepAlive: servicio detenido');
    } catch (e) {
      debugPrint('ForegroundKeepAlive: error deteniendo: $e');
    }
  }
}
