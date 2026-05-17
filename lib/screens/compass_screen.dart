import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../models/member.dart';
import '../services/group_controller.dart';
import '../utils/distance_calculator.dart';

class CompassScreen extends StatefulWidget {
  final String targetMemberId;

  const CompassScreen({super.key, required this.targetMemberId});

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen> {
  double _userHeading = 0.0;
  double _animatedAngle = 0.0;
  double? _previousDistance;
  String _distanceTrend = '—';
  Color _trendColor = AppTheme.textMuted;
  IconData _trendIcon = Icons.remove;

  StreamSubscription<double>? _headingSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final location = context.read<GroupController>().location;
      _userHeading = location.lastHeading ?? 0.0;
      _headingSub = location.headingStream.listen((heading) {
        if (!mounted) return;
        setState(() {
          _userHeading = heading;
        });
        _updateDistanceTrend();
      });
    });
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    super.dispose();
  }

  void _updateDistanceTrend() {
    final controller = context.read<GroupController>();
    final group = controller.group;
    if (group == null) return;

    final target = group.members.firstWhere(
      (m) => m.id == widget.targetMemberId,
      orElse: () => group.self!,
    );

    final currentDistance = DistanceCalculator.between(
      group.self?.lastPosition,
      target.lastPosition,
    ).meters;

    if (_previousDistance != null) {
      if (currentDistance < _previousDistance! - 0.5) {
        _distanceTrend = '↘ Acercándote';
        _trendColor = AppTheme.accentGreen;
        _trendIcon = Icons.arrow_downward;
      } else if (currentDistance > _previousDistance! + 0.5) {
        _distanceTrend = '↗ Alejándote';
        _trendColor = const Color(0xFFEF9F27);
        _trendIcon = Icons.arrow_upward;
      } else {
        _distanceTrend = '— Estable';
        _trendColor = AppTheme.textMuted;
        _trendIcon = Icons.remove;
      }
    }

    _previousDistance = currentDistance;
  }

  String _cardinalFromAngle(double degrees) {
    if (degrees >= 337.5 || degrees < 22.5) return 'N';
    if (degrees < 67.5) return 'NE';
    if (degrees < 112.5) return 'E';
    if (degrees < 157.5) return 'SE';
    if (degrees < 202.5) return 'S';
    if (degrees < 247.5) return 'SO';
    if (degrees < 292.5) return 'O';
    return 'NO';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final group = controller.group;
    if (group == null) return const Scaffold();

    final target = group.members.firstWhere(
      (m) => m.id == widget.targetMemberId,
      orElse: () => group.self!,
    );

    final selfPos = group.self?.lastPosition;
    final result = DistanceCalculator.between(selfPos, target.lastPosition);
    final hasDirection = result.bearing != null;
    final relativeAngle = hasDirection
        ? (result.bearing! - _userHeading + 360) % 360
        : 0.0;

    final distanceText = result.source != DistanceSource.none
        ? '~${result.meters.toStringAsFixed(0)} m'
        : 'Sin posición';

    final headingText = '${_userHeading.toStringAsFixed(0)}° ${_cardinalFromAngle(_userHeading)}';
    final bearingText = result.bearing != null
        ? '${result.bearing!.toStringAsFixed(0)}°'
        : (result.source == DistanceSource.rssi ? 'Estimado por BT' : 'Sin datos GPS');
    final precisionText = selfPos?.accuracy != null
        ? '±${selfPos!.accuracy!.toStringAsFixed(0)} m'
        : (selfPos == null ? 'Sin GPS activo' : 'Sin precisión');
    final statusColor = target.status == MemberStatus.online
        ? AppTheme.accentGreen
        : AppTheme.textMuted;
    final statusLabel = target.status == MemberStatus.online
        ? 'En línea'
        : 'Sin señal reciente';

    return Scaffold(
      appBar: AppBar(
        title: Text('Buscando a ${target.displayName}'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(statusLabel,
                            style: TextStyle(color: statusColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_distanceTrend,
                        style: TextStyle(color: _trendColor, fontSize: 12)),
                  ),
                ],
              ),
              if (result.source == DistanceSource.rssi && !hasDirection)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E4625),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Sin GPS activo: usando solo proximidad BT para mantener la búsqueda activa. PIN ${group.code}',
                      style: const TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: _buildCompassRing(relativeAngle, result.source != DistanceSource.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildStatsRow(
                      headingText: headingText,
                      bearingText: bearingText,
                      precisionText: precisionText,
                    ),
                    const SizedBox(height: 16),
                    _buildDistanceCard(distanceText, result.errorMeters),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentGreen,
                    side: const BorderSide(color: AppTheme.accentGreen),
                  ),
                  child: const Text('Volver al radar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompassRing(double relativeAngle, bool hasTarget) {
    return Container(
      width: 290,
      height: 290,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.18), width: 1.5),
        color: AppTheme.cardBg,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.08), width: 1),
            ),
          ),
          _cardinalLabel('N', 0),
          _cardinalLabel('E', 90),
          _cardinalLabel('S', 180),
          _cardinalLabel('O', 270),
          TweenAnimationBuilder<double>(
            tween: _AngleTween(begin: _animatedAngle, end: relativeAngle),
            duration: const Duration(milliseconds: 300),
            builder: (context, angle, child) {
              _animatedAngle = angle;
              return Transform.rotate(
                angle: angle * pi / 180,
                child: child,
              );
            },
            child: Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.scaffoldBg,
              ),
              child: Center(
                child: Icon(Icons.navigation,
                    size: 92,
                    color: hasTarget ? AppTheme.accentGreen : AppTheme.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardinalLabel(String label, double degrees) {
    return Positioned(
      top: degrees == 0 ? 18 : null,
      bottom: degrees == 180 ? 18 : null,
      left: degrees == 270 ? 18 : null,
      right: degrees == 90 ? 18 : null,
      child: Text(label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w700,
          )),
    );
  }

  Widget _buildStatsRow({
    required String headingText,
    required String bearingText,
    required String precisionText,
  }) {
    return Row(
      children: [
        Expanded(child: _metricCard('Brújula', headingText)),
        const SizedBox(width: 10),
        Expanded(child: _metricCard('Bearing', bearingText)),
        const SizedBox(width: 10),
        Expanded(child: _metricCard('Precisión', precisionText)),
      ],
    );
  }

  Widget _metricCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildDistanceCard(String distanceText, double? errorMeters) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(distanceText,
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Distancia estimada',
                    style: TextStyle(color: AppTheme.textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _trendColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_trendIcon, color: _trendColor, size: 22),
          ),
        ],
      ),
    );
  }
}

class _AngleTween extends Tween<double> {
  _AngleTween({super.begin, super.end});

  @override
  double lerp(double t) {
    final start = begin ?? 0;
    final target = end ?? 0;
    final delta = ((target - start + 540) % 360) - 180;
    return (start + delta * t + 360) % 360;
  }
}
