import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/position.dart' as model;

/// Servicio que obtiene la posición GPS del usuario y el rumbo de la brújula.
///
/// La frecuencia de actualización está dosificada para no quemar batería:
///  - GPS continuo con `distanceFilter: 2` metros — solo emite si te moviste.
///  - Brújula en stream nativo — el costo es despreciable.
///
/// Para festivales, donde puede haber muchas paredes/cuerpos bloqueando
/// satélites, la `accuracy` reportada puede subir a 10-30 m. Eso lo
/// pintamos en la UI como "±N metros" para que el usuario sepa lo
/// confiable que es la posición de sus amigos.
class LocationService {
  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;

  final _positionCtrl = StreamController<model.Position>.broadcast();
  final _headingCtrl = StreamController<double>.broadcast();

  double? _lastHeading;
  model.Position? _lastPosition;

  Stream<model.Position> get positionStream => _positionCtrl.stream;
  Stream<double> get headingStream => _headingCtrl.stream;

  model.Position? get lastPosition => _lastPosition;
  double? get lastHeading => _lastHeading;

  /// Solicita los permisos en este orden: location → location always
  /// (background opcional). En iOS se requiere `whenInUse` mínimo.
  /// También solicita permisos de Bluetooth necesarios para Nearby Connections.
  Future<bool> requestPermissions() async {
    // Primero ubicación
    final fineStatus = await Permission.locationWhenInUse.request();
    if (!fineStatus.isGranted) {
      debugPrint('LocationService: permiso de ubicación denegado');
      return false;
    }

    // Luego Bluetooth (necesario para Nearby Connections)
    final bluetoothScan = await Permission.bluetoothScan.request();
    final bluetoothAdvertise = await Permission.bluetoothAdvertise.request();
    final bluetoothConnect = await Permission.bluetoothConnect.request();

    if (!bluetoothScan.isGranted || !bluetoothAdvertise.isGranted || !bluetoothConnect.isGranted) {
      debugPrint('LocationService: permisos de Bluetooth denegados');
      // No fallamos por Bluetooth, ya que algunos dispositivos pueden funcionar sin él
      // pero Nearby Connections será limitado
    }

    return true;
  }

  Future<void> start() async {
    final granted = await requestPermissions();
    if (!granted) {
      throw StateError('Permisos de ubicación denegados');
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (serviceEnabled) {
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ),
      ).listen(
        (gpsPos) {
          final pos = model.Position(
            latitude: gpsPos.latitude,
            longitude: gpsPos.longitude,
            accuracy: gpsPos.accuracy,
            heading: gpsPos.heading >= 0 ? gpsPos.heading : null,
            timestamp: DateTime.now(),
          );
          _lastPosition = pos;
          _positionCtrl.add(pos);
        },
        onError: (e) => debugPrint('LocationService: error GPS: $e'),
      );
    } else {
      debugPrint('LocationService: GPS desactivado, solo brújula habilitada');
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null) {
        final pos = model.Position(
          latitude: cached.latitude,
          longitude: cached.longitude,
          accuracy: cached.accuracy,
          heading: cached.heading >= 0 ? cached.heading : null,
          timestamp: DateTime.now(),
        );
        _lastPosition = pos;
        _positionCtrl.add(pos);
      }
    }

    _compassSub = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (heading == null) return;
      _lastHeading = heading;
      _headingCtrl.add(heading);
    });
  }

  Future<void> stop() async {
    await _posSub?.cancel();
    await _compassSub?.cancel();
    _posSub = null;
    _compassSub = null;
  }

  void dispose() {
    stop();
    _positionCtrl.close();
    _headingCtrl.close();
  }
}
