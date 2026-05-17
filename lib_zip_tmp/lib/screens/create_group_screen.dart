import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/theme/app_theme.dart';
import '../services/group_controller.dart';
import 'radar_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController(text: 'Mi grupo');
  final _myNameCtrl = TextEditingController();
  bool _creating = false;
  String? _generatedCode;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _myNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating) return;
    if (_myNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe tu nombre')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      // Solicitar permisos antes de crear el grupo
      final controller = context.read<GroupController>();
      final locationGranted = await controller.location.requestPermissions();
      if (!locationGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se necesitan permisos de ubicación para continuar'),
            duration: Duration(seconds: 5),
          ),
        );
        setState(() => _creating = false);
        return;
      }

      // Verificar específicamente permisos de Bluetooth
      final bluetoothScan = await Permission.bluetoothScan.status;
      final bluetoothAdvertise = await Permission.bluetoothAdvertise.status;
      final bluetoothConnect = await Permission.bluetoothConnect.status;

      if (!bluetoothScan.isGranted || !bluetoothAdvertise.isGranted || !bluetoothConnect.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se necesitan permisos de Bluetooth para conectar con otros dispositivos'),
            duration: Duration(seconds: 5),
          ),
        );
        // Intentar solicitar permisos nuevamente
        await Permission.bluetoothScan.request();
        await Permission.bluetoothAdvertise.request();
        await Permission.bluetoothConnect.request();
      }

      final group = await controller.createGroup(
        groupName: _nameCtrl.text.trim().isEmpty ? 'Grupo' : _nameCtrl.text.trim(),
        myDisplayName: _myNameCtrl.text.trim(),
      );
      setState(() => _generatedCode = group.code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _enterRadar() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RadarScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = _generatedCode;
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo grupo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: code == null
              ? _buildForm()
              : _buildCreated(code),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Nombre del grupo',
            style: TextStyle(color: AppTheme.textMuted)),
        const SizedBox(height: 8),
        TextField(controller: _nameCtrl),
        const SizedBox(height: 20),
        const Text('Tu nombre',
            style: TextStyle(color: AppTheme.textMuted)),
        const SizedBox(height: 8),
        TextField(controller: _myNameCtrl),
        const Spacer(),
        ElevatedButton(
          onPressed: _creating ? null : _create,
          child: _creating
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.black, strokeWidth: 2),
                )
              : const Text('Crear grupo'),
        ),
      ],
    );
  }

  Widget _buildCreated(String code) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Comparte este código',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'Tus amigos lo pueden escanear o teclear para entrar.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        const SizedBox(height: 28),
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: code,
              version: QrVersions.auto,
              size: 220,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Text('Código del grupo',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              SelectableText(
                code,
                style: const TextStyle(
                  color: AppTheme.accentGreen,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código copiado')),
                  );
                },
              ),
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: _enterRadar,
          child: const Text('Entrar al radar'),
        ),
      ],
    );
  }
}
