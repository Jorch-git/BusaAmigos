import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../services/ble/ble_proximity_service.dart';
import '../services/ble/rssi_calibration.dart';
import '../services/group_controller.dart';
import '../utils/short_id.dart';

/// Pantalla de calibración y diagnóstico BLE. Permite:
///  - Ver en vivo el RSSI de cada miembro detectado por BLE.
///  - Calibrar la conversión RSSI→distancia poniendo los teléfonos a una
///    distancia conocida (1 m, 5 m) y registrando la lectura.
///  - Ajustar manualmente txPower y el factor de atenuación n.
///
/// Se arranca el escaneo BLE al entrar y se detiene al salir.
class BleCalibrationScreen extends StatefulWidget {
  const BleCalibrationScreen({super.key});

  @override
  State<BleCalibrationScreen> createState() => _BleCalibrationScreenState();
}

class _BleCalibrationScreenState extends State<BleCalibrationScreen> {
  Timer? _refresh;
  StreamSubscription<void>? _bleSub;
  final _calib = RssiCalibration.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selfId = context.read<GroupController>().group?.self?.id;
      if (selfId != null && !BleProximityService.instance.isRunning) {
        BleProximityService.instance.start(selfMemberId: selfId);
      }
      _bleSub = BleProximityService.instance.updates.listen((_) {
        if (mounted) setState(() {});
      });
    });
    // Refresco periódico por si no llegan eventos.
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _bleSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final group = controller.group;
    final others = group?.others ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Calibración BLE')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _infoCard(),
            const SizedBox(height: 20),

            _sectionTitle('LECTURAS EN VIVO'),
            const SizedBox(height: 8),
            if (others.isEmpty)
              _card(child: _muted('No hay otros miembros en el grupo.'))
            else
              ...others.map((m) => _memberReading(m.id, m.displayName)),

            const SizedBox(height: 20),
            _sectionTitle('CALIBRACIÓN'),
            const SizedBox(height: 8),
            _calibCard(),

            const SizedBox(height: 20),
            _sectionTitle('PARÁMETROS ACTUALES'),
            const SizedBox(height: 8),
            _paramsCard(),
          ],
        ),
      ),
    );
  }

  Widget _memberReading(String memberId, String name) {
    final rssi = BleProximityService.instance.rssiForMember(memberId);
    final shortId = ShortId.of(memberId);
    final hasReading = rssi != null;
    final dist = hasReading ? _calib.distanceFromRssi(rssi) : null;

    return _card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: hasReading
                  ? AppTheme.accentGreen.withValues(alpha: 0.15)
                  : AppTheme.scaffoldBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hasReading ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              size: 18,
              color: hasReading ? AppTheme.accentGreen : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text('short id: 0x${shortId.toRadixString(16)}',
                    style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasReading ? '$rssi dBm' : 'sin señal',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  fontFamily: 'monospace',
                  color: hasReading ? AppTheme.accentGreen : AppTheme.textMuted,
                ),
              ),
              if (dist != null)
                Text('≈ ${dist.toStringAsFixed(1)} m',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calibCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _muted(
              'Pon los dos teléfonos a la distancia indicada y toca el botón. '
              'Se usará la lectura del primer miembro con señal.'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _calibButton('Calibrar a 1 m', 1.0),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _calibButton('Calibrar a 5 m', 5.0),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Restaurar valores por defecto'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: AppTheme.textMuted,
              side: const BorderSide(color: AppTheme.textMuted),
            ),
            onPressed: () async {
              await _calib.reset();
              if (mounted) {
                setState(() {});
                _toast('Calibración restaurada a valores por defecto');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _calibButton(String label, double meters) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: AppTheme.accentGreen,
        foregroundColor: Colors.black,
      ),
      onPressed: () => _doCalibrate(meters),
      child: Text(label, textAlign: TextAlign.center),
    );
  }

  Future<void> _doCalibrate(double meters) async {
    // Buscar el primer miembro con lectura BLE.
    final controller = context.read<GroupController>();
    final others = controller.group?.others ?? [];
    int? rssi;
    for (final m in others) {
      final r = BleProximityService.instance.rssiForMember(m.id);
      if (r != null) {
        rssi = r;
        break;
      }
    }
    if (rssi == null) {
      _toast('No hay señal BLE de ningún miembro. Acerca los teléfonos.');
      return;
    }
    await _calib.calibrateFrom(measuredRssi: rssi, knownMeters: meters);
    if (mounted) {
      setState(() {});
      _toast('Calibrado a $meters m con RSSI $rssi dBm');
    }
  }

  Widget _paramsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paramRow('TxPower (RSSI a 1 m)',
              '${_calib.txPowerAt1m.toStringAsFixed(0)} dBm'),
          const SizedBox(height: 10),
          _slider(
            value: _calib.txPowerAt1m,
            min: -80,
            max: -40,
            label: 'TxPower',
            onChanged: (v) {
              setState(() => _calib.txPowerAt1m = v);
            },
            onEnd: (_) => _calib.save(),
          ),
          const SizedBox(height: 14),
          _paramRow('Factor de atenuación (n)',
              _calib.pathLossN.toStringAsFixed(2)),
          const SizedBox(height: 4),
          _muted('2.0 = espacio abierto · 2.5-3.0 = con gente/obstáculos'),
          const SizedBox(height: 6),
          _slider(
            value: _calib.pathLossN,
            min: 1.5,
            max: 4.0,
            label: 'n',
            onChanged: (v) {
              setState(() => _calib.pathLossN = v);
            },
            onEnd: (_) => _calib.save(),
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    required String label,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onEnd,
  }) {
    return Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      activeColor: AppTheme.accentGreen,
      label: label,
      onChanged: onChanged,
      onChangeEnd: onEnd,
    );
  }

  Widget _paramRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                fontFamily: 'monospace',
                color: AppTheme.accentGreen)),
      ],
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppTheme.accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'El RSSI (señal BLE) sirve para proximidad fina entre Android. '
              'Es ruidoso: un cuerpo o el bolsillo lo afectan. Calibrar mejora '
              'la conversión a metros para tus teléfonos.',
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
          color: AppTheme.accentGreen,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 1),
    );
  }

  Widget _card({required Widget child, EdgeInsets? margin}) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _muted(String text) => Text(text,
      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.4));

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
