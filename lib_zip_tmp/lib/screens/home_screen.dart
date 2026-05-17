import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../services/group_controller.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';
import 'radar_screen.dart';

/// Pantalla inicial: si ya hay un grupo activo, te manda al radar.
/// Si no, ofrece crear o unirse.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    if (controller.group != null) {
      return const RadarScreen();
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Text(
                'Buscamigos',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Encuentra a tu grupo en festivales, conciertos\ny eventos masivos.',
                style: TextStyle(color: AppTheme.textMuted, height: 1.5),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Crear nuevo grupo'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const JoinGroupScreen()),
                ),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Unirme a un grupo'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  side: const BorderSide(color: AppTheme.accentGreen),
                  foregroundColor: AppTheme.accentGreen,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
