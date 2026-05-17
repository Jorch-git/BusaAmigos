import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/group_controller.dart';
import 'services/group_storage.dart';
import 'services/location/location_service.dart';
import 'services/transport/nearby/nearby_transport.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final transport = NearbyTransport();
  final location = LocationService();
  final storage = GroupStorage();
  final controller = GroupController(
    location: location,
    transport: transport,
    storage: storage,
  );
  await controller.loadSavedGroup();

  runApp(
    ChangeNotifierProvider(
      create: (_) => controller,
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
