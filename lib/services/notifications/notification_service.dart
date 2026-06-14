import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servicio centralizado de notificaciones pop locales.
///
/// Dos canales:
///  - `messages`: mensajes de chat entrantes. Importancia normal.
///  - `sos`: alertas de emergencia. Importancia máxima, con sonido y
///    vibración insistente, salta por encima de todo.
///
/// IMPORTANTE sobre el alcance: estas notificaciones se disparan cuando la
/// app está corriendo (primer plano o segundo plano con foreground service).
/// Si la app fue MATADA por completo (deslizada de recientes) o por el SO,
/// no hay forma de despertarla sin un push server. El foreground service
/// (ver ForegroundKeepAlive) mantiene la app viva para que esto funcione
/// con pantalla apagada.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Callback que la app puede setear para reaccionar a taps en notificaciones.
  /// El payload identifica qué abrir (ej. 'chat' o 'sos').
  void Function(String? payload)? onTap;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        onTap?.call(resp.payload);
      },
    );

    // Crear canales Android explícitamente (Android 8+).
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'messages',
          'Mensajes',
          description: 'Mensajes del chat de grupo',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'sos',
          'Alertas SOS',
          description: 'Alertas de emergencia del grupo',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    _initialized = true;
  }

  /// Pide permiso de notificaciones (Android 13+ e iOS).
  Future<bool> requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
          alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return false;
  }

  /// Notificación de mensaje de chat entrante.
  Future<void> showMessage({
    required String senderName,
    required String text,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        // ID basado en hash del sender para que mensajes del mismo emisor
        // se agrupen/reemplacen en vez de apilarse infinitamente.
        senderName.hashCode & 0x7fffffff,
        senderName,
        text,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Mensajes',
            channelDescription: 'Mensajes del chat de grupo',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(''),
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: 'chat',
      );
    } catch (e) {
      debugPrint('NotificationService: error showMessage: $e');
    }
  }

  /// Notificación de alerta SOS — máxima prioridad.
  Future<void> showSos({
    required String triggeredByName,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        999001, // ID fijo: solo un SOS a la vez.
        '🚨 ALERTA DE EMERGENCIA',
        '$triggeredByName necesita ayuda',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'sos',
            'Alertas SOS',
            channelDescription: 'Alertas de emergencia del grupo',
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            color: Color.fromARGB(255, 226, 75, 74),
            colorized: true,
          ),
          iOS: DarwinNotificationDetails(
            interruptionLevel: InterruptionLevel.critical,
          ),
        ),
        payload: 'sos',
      );
    } catch (e) {
      debugPrint('NotificationService: error showSos: $e');
    }
  }

  /// Limpia todas las notificaciones (ej. al abrir el chat).
  Future<void> clearMessages() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
