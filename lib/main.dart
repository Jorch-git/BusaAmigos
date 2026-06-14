import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import 'config/theme/app_theme.dart';
import 'config/theme/theme_controller.dart';
import 'screens/home_screen.dart';
import 'services/group_controller.dart';
import 'services/group_storage.dart';
import 'services/location/location_service.dart';
import 'services/logging/event_log_service.dart';
import 'services/notifications/notification_service.dart';
import 'services/notifications/foreground_service.dart';
import 'services/map/tile_cache_service.dart';
import 'services/sensors/beacon_config.dart';
import 'services/sensors/sensor_fusion_service.dart';
import 'services/transport/nearby/nearby_transport.dart';
import 'services/transport/mesh/mesh_transport.dart';
import 'services/transport/mesh/mesh_profile.dart';
import 'services/transport/hybrid/hybrid_transport.dart';
// import 'services/transport/relay/relay_transport.dart'; // para alcance global

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Necesario para que el foreground task pueda comunicarse con la UI.
  FlutterForegroundTask.initCommunicationPort();

  // Inicializa notificaciones locales y el servicio de foreground.
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermission();
  ForegroundKeepAlive.instance.init();

  // Inicializa el caché de tiles del mapa (offline).
  await TileCacheService.instance.init();

  const beaconConfig = BeaconConfig();

  // ---- Transporte: mesh multi-hop local sobre Nearby (gratis, offline) ----
  final nearby = NearbyTransport();
  final mesh = MeshTransport(nearby, profile: MeshProfile.highDensity);
  final transport = HybridTransport(mesh /*, relay: relay*/);

  final location = LocationService();
  final storage = GroupStorage();
  final sensors = SensorFusionService(config: beaconConfig);
  final eventLog = EventLogService();

  final controller = GroupController(
    location: location,
    transport: transport,
    storage: storage,
    sensors: sensors,
    eventLog: eventLog,
    config: beaconConfig,
  );
  await controller.loadSavedGroup();

  // Tema (claro/oscuro) persistido.
  final themeController = ThemeController();
  await themeController.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: eventLog),
        ChangeNotifierProvider.value(value: themeController),
      ],
      child: const BuscamigosApp(),
    ),
  );
}

class BuscamigosApp extends StatelessWidget {
  const BuscamigosApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Escucha el ThemeController para alternar tema en caliente.
    final themeController = context.watch<ThemeController>();

    // Envolvemos en WithForegroundTask para que el servicio funcione bien.
    return MaterialApp(
      title: 'Buscamigos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeController.mode,
      builder: (context, child) {
        return WithForegroundTask(
          child: child ?? const SizedBox(),
        );
      },
      home: const HomeScreen(),
    );
  }
}
