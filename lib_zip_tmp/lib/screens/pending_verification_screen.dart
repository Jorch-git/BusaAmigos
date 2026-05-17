import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../services/group_controller.dart';
import 'home_screen.dart';
import 'radar_screen.dart';

/// Pantalla mostrada justo después de que B escanea el QR de A. Espera a
/// recibir un Hello/Position de algún miembro existente (verificación
/// física) antes de dejar pasar al radar. Si pasa de los 60s sin detectar
/// a nadie, ofrece dos salidas: salir del grupo o entrar de todas formas.
///
/// IMPORTANTE: La navegación al radar se hace mediante un addListener en el
/// ChangeNotifier, NO desde el build. Si lo pones en build() con
/// addPostFrameCallback, cada notifyListeners() (heartbeat cada 5s, etc)
/// reagenda otra navegación y la app entra en cascada de pushes.
class PendingVerificationScreen extends StatefulWidget {
  const PendingVerificationScreen({super.key});

  @override
  State<PendingVerificationScreen> createState() =>
      _PendingVerificationScreenState();
}

class _PendingVerificationScreenState
    extends State<PendingVerificationScreen> {
  GroupController? _controller;
  bool _navigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Adjuntamos el listener una sola vez. didChangeDependencies se llama
    // cuando ya tenemos contexto válido para Provider.of.
    if (_controller != null) return;
    _controller = Provider.of<GroupController>(context, listen: false);
    _controller!.addListener(_onControllerChanged);
    // Por si el estado ya está confirmado al entrar.
    _maybeNavigate(_controller!.verificationState);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _maybeNavigate(_controller!.verificationState);
  }

  void _maybeNavigate(GroupVerificationState state) {
    if (_navigated) return;
    if (state == GroupVerificationState.confirmed ||
        state == GroupVerificationState.notRequired) {
      _navigated = true;
      // Navegamos en el siguiente microtask para no chocar con el frame actual.
      Future.microtask(() {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RadarScreen()),
          (_) => false,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Aquí SÍ podemos usar watch porque solo lo leemos para decidir qué
    // pintar. La navegación va por listener, no por build.
    final controller = context.watch<GroupController>();
    final state = controller.verificationState;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: state == GroupVerificationState.timedOut
                ? _buildTimedOut(context, controller)
                : _buildPending(context, controller),
          ),
        ),
      ),
    );
  }

  Widget _buildPending(BuildContext context, GroupController controller) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: AppTheme.accentGreen,
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Buscando al grupo cerca…',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Asegúrate de estar a menos de 30 metros del organizador y de\n'
          'que ambos tienen Bluetooth y WiFi activados.',
          style: TextStyle(color: AppTheme.textMuted, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: () async {
            // Salir limpiamente: removemos el listener antes de leaveGroup
            // porque leaveGroup notifica con state=notRequired y eso
            // dispararía una navegación que ya no queremos.
            _navigated = true;
            final navigator = Navigator.of(context);
            await controller.leaveGroup();
            if (!mounted) return;
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (_) => false,
            );
          },
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _buildTimedOut(BuildContext context, GroupController controller) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.location_off, size: 80, color: AppTheme.sosRed),
        const SizedBox(height: 32),
        const Text(
          'No detectamos al grupo cerca',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Ningún miembro fue detectado en proximidad física durante los\n'
          'últimos 60 segundos. Esto suele significar que estás muy lejos del\n'
          'organizador, o que hay interferencia bloqueando el Bluetooth/WiFi.',
          style: TextStyle(color: AppTheme.textMuted, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppTheme.textMuted),
            ),
            onPressed: () async {
              _navigated = true;
              final navigator = Navigator.of(context);
              await controller.leaveGroup();
              if (!mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (_) => false,
              );
            },
            child: const Text('Salir del grupo'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () {
              // Esto cambia verificationState a notRequired,
              // el listener detectará el cambio y navegará al radar.
              controller.acceptUnverifiedGroup();
            },
            child: const Text('Entrar de todas formas'),
          ),
        ),
      ],
    );
  }
}
