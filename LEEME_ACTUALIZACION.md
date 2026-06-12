# Actualización Buscamigos

## Qué hay de nuevo en esta versión
1. **Rastreo con fusión de sensores** (acelerómetro + giroscopio + magnetómetro):
   rumbo suave por filtro complementario, detección de pasos y dead reckoning.
2. **Beacon configurable a 1 s**, comprimido (gzip) + cifrado.
3. **Log de eventos descargable** (JSON + CSV), legible y sin comprimir.
4. **Transporte HÍBRIDO con mesh multi-hop** — la alternativa a Bridgefy, gratis
   y sin depender de nadie. Ver abajo.

## Cómo instalar
1. Reemplaza **toda** tu carpeta `lib/` por la de este paquete.
2. Reemplaza tu `pubspec.yaml` y corre `flutter pub get`.
3. Agrega permisos a tus manifests (sección "Permisos").
4. `flutter analyze` y a probar.

---

## El transporte híbrido (mesh + relay)

```
HybridTransport
 ├── MeshTransport(NearbyTransport)   ← malla local multi-hop, OFFLINE, gratis
 └── RelayTransport(wss://...)        ← OPCIONAL: tu servidor, alcance global
```

**Qué resuelve el mesh que tu Nearby NO hacía:** hoy solo hablan los peers
conectados directo. Con el mesh, si A y C no se ven pero ambos ven a B, el
mensaje salta por B hasta C. Eso es lo que da estabilidad en multitudes (es lo
que hace Bridgefy). Incluye:
- **dedupe** por id de mensaje (rompe bucles),
- **TTL + hop count** (el mensaje muere tras N saltos),
- **gossip + jitter** (reenvío probabilístico y con retardo aleatorio para no
  saturar el aire en multitudes).

Se configura con `MeshProfile`: `standard`, `highDensity` (multitudes),
`sparse`, `longReach`. Por defecto va `highDensity`. Cámbialo en `main.dart`.

**El relay es OPCIONAL.** Sin él, todo funciona en modo local (no dependes de
nadie). Si levantas tu propio servidor WebSocket (ejemplo de Node incluido en
`relay_transport.dart`), ganas alcance global e iOS↔Android **con internet**.
Para activarlo, en `main.dart`:
```dart
final relay = RelayTransport('wss://tu-servidor:8080');
final transport = HybridTransport(mesh, relay: relay);
```

**Límite honesto:** iOS↔Android **offline** no es posible gratis (límite del
ecosistema móvil). El mesh local cubre Android↔Android; el cruce de plataformas
solo ocurre vía relay (con internet).

### Cómo afinar tráfico si algún día escala a MUCHA gente
Ahora el mesh reenvía todo sobre que recibe (igual que Bridgefy), aunque sea de
otro grupo, porque el payload va cifrado y no sabe de qué grupo es. Para grupos
de festival (pocas personas) está bien. Si hubiera cientos de grupos buscamigos
cerca, añade un `channelId` (hash del código) a `MeshEnvelope` y reenvía solo
los de tu canal. Es una optimización, no la necesitas de entrada.

---

## Archivos nuevos
- `services/sensors/` — imu_types, sensor_fusion_service, beacon_config
- `services/transport/codec/payload_codec.dart` — gzip + cifrado
- `services/transport/mesh/` — mesh_profile, mesh_envelope, mesh_transport
- `services/transport/hybrid/hybrid_transport.dart`
- `services/logging/` — event_log_service, log_exporter
- `screens/event_log_screen.dart`

## Archivos modificados
- `main.dart` — HybridTransport(mesh sobre Nearby) + Providers
- `services/group_controller.dart` — fusión, beacon 1 s, codec, log, dead reckoning
- `services/transport/relay/relay_transport.dart` — ahora es un relay WebSocket real
- `services/crypto/group_crypto.dart` — +encryptBytes/decryptBytes
- `models/position.dart` — +rumbo fusionado, tilt, pasos, dead reckoning
- `widgets/compass_arrow.dart` — flecha animada
- `screens/settings_screen.dart` — acceso al "Registro de la sesión"

---

## Permisos (NO tengo tus manifests; agrégalos tú)

**iOS — `ios/Runner/Info.plist`** (requerido por sensors_plus o crashea):
```xml
<key>NSMotionUsageDescription</key>
<string>Buscamigos usa los sensores de movimiento para mejorar el rastreo de tu grupo.</string>
```

**Android — `android/app/src/main/AndroidManifest.xml`** (opcional, solo si
subes el muestreo por encima de ~200 Hz):
```xml
<uses-permission android:name="android.permission.HIGH_SAMPLING_RATE_SENSORS"/>
```

---

## Consola de desarrollo (opcional)
`MeshTransport` expone `meshStats` (originados, entregados, reenviados,
duplicados, ids vistos). Para verlo en tu Consola, donde hoy castea a
`NearbyTransport`, puedes castear a `HybridTransport`/`MeshTransport`:
```dart
final t = controller.transport;
if (t is HybridTransport) { final stats = t.mesh.meshStats; /* píntalo */ }
```

## Notas
- Beacon a 1 s. Ajústalo en caliente:
  `context.read<GroupController>().updateConfig(controller.config.copyWith(beaconInterval: Duration(milliseconds: 500)))`.
- Posiciones `deadReckoned: true` = estimadas (GPS viejo); píntalas distinto en el radar.
- El rumbo tilt-compensado puede necesitar ajuste de signo según tu equipo
  (comentado en `sensor_fusion_service.dart`); compáralo con `flutter_compass`.
- `opcional_bridgefy/` queda como alternativa si algún día decides usar Bridgefy.
- Nada de esto se compiló aquí (no hay Flutter en el entorno): corre `flutter analyze`.
