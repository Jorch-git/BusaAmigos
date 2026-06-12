import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/group_controller.dart';
import 'services/group_storage.dart';
import 'services/location/location_service.dart';
import 'services/logging/event_log_service.dart';
import 'services/sensors/beacon_config.dart';
import 'services/sensors/sensor_fusion_service.dart';
import 'services/transport/nearby/nearby_transport.dart';
import 'services/transport/mesh/mesh_transport.dart';
import 'services/transport/mesh/mesh_profile.dart';
import 'services/transport/hybrid/hybrid_transport.dart';
// import 'services/transport/relay/relay_transport.dart'; // para alcance global

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Config del beacon/sensores. beaconInterval = 1 s (ajustable en caliente).
  const beaconConfig = BeaconConfig();

  // ---- Transporte: mesh multi-hop local sobre Nearby (gratis, offline) ----
  // El mesh convierte el Nearby (solo peers directos) en una malla que reenvía
  // de salto en salto. Perfil highDensity = pensado para multitudes.
  final nearby = NearbyTransport();
  final mesh = MeshTransport(nearby, profile: MeshProfile.highDensity);

  // Relay OPCIONAL: tu propio servidor WebSocket para alcance global y cruce
  // iOS<->Android cuando hay internet. Sin él, todo funciona en modo local.
  // final relay = RelayTransport('wss://tu-servidor:8080');

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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: eventLog),
      ],
      child: const BuscamigosApp(),
    ),
  );
}

class BuscamigosApp extends StatelessWidget {
  const BuscamigosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buscamigos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
