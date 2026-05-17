import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/group_controller.dart';
import 'services/location/location_service.dart';
import 'services/transport/nearby/nearby_transport.dart';

void main() {
  // Para producción real, usamos NearbyTransport para comunicación P2P
  // entre dispositivos cercanos (Bluetooth/WiFi Direct)
  final transport = NearbyTransport();
  final location = LocationService();

  runApp(
    ChangeNotifierProvider(
      create: (_) => GroupController(location: location, transport: transport),
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
