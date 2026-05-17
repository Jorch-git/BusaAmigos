# Buscamigos

Encuentra a tu grupo en festivales, conciertos y eventos masivos. Híbrido: GPS + relay cuando hay internet, BLE/Wi-Fi Direct cuando no.

App Flutter (Android + iOS) derivada del proyecto `buscabeacon`. Reutiliza la matemática del radar circular y la lógica RSSI; el resto es nuevo.

---

## Cómo correrlo por primera vez

Como el zip incluye solo `lib/`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` y `pubspec.yaml`, hay que regenerar el resto del andamiaje de Flutter:

```bash
cd buscamigos
flutter create . --org com.tunombre --platforms=android,ios
flutter pub get
flutter run
```

`flutter create .` no borra archivos existentes — solo agrega los faltantes (Gradle, project.pbxproj, etc.). El `AndroidManifest.xml` y `Info.plist` ya cargados se respetan.

> Si `flutter create` sobrescribe el AndroidManifest, restaura el del repo: el de Flutter por defecto no incluye los permisos de Bluetooth/WiFi/Cámara/Location que necesitamos.

### Versiones probadas
- Flutter ≥ 3.24
- Dart ≥ 3.5
- Android: minSdk 23, targetSdk 34
- iOS: iOS 13+ (MultipeerConnectivity requiere ≥ 12; con 13+ todo lo demás funciona)

---

## Probar sin amigos: modo ghosts

Por defecto la app arranca con `FakeRelayTransport(enableGhosts: true)`. Esto significa:

- **No hay servidor real**: las instancias de la app se comunican entre sí solo dentro del mismo proceso. Útil para tests automatizados o para correr dos `flutter run` apuntando al mismo simulador, no entre celulares físicos.
- **Aparecen 4 miembros simulados** (Juan, Pedro, Ana, María) que orbitan el Foro Sol en CDMX a 8–50 m del centro. Cada 2 s mandan posición. Sirve para ver el radar lleno mientras tu GPS apunta a CDMX (en otro lugar también funciona, pero los ghosts siguen "estando" en CDMX).

Para apagar los fantasmas:

```dart
// lib/main.dart
final transport = FakeRelayTransport(enableGhosts: false);
```

---

## Estructura del proyecto

```
lib/
  main.dart                                # composición de servicios + runApp
  config/theme/app_theme.dart              # paleta dark verde-neón #1DD27D
  models/                                  # Group, Member, Position, ChatMessage, SosAlert
  services/
    crypto/
      group_code.dart                      # genera/valida XXX-XXXXXX (Crockford-Base32)
      group_crypto.dart                    # Argon2id → XChaCha20-Poly1305 (E2E)
    location/location_service.dart         # GPS + brújula
    transport/
      transport_service.dart               # interfaz abstracta
      transport_message.dart               # tipos sealed: Hello, Position, Chat, Sos, ...
      fake/fake_relay_transport.dart       # mock con bus en memoria + ghosts
      relay/relay_transport.dart           # placeholder (Firebase/Supabase/propio)
      nearby/nearby_transport.dart         # P2P real (Nearby + MultipeerConnectivity)
    group_controller.dart                  # ChangeNotifier: orquesta todo
  screens/                                 # 9 pantallas, el flujo del video
  widgets/                                 # radar, brújula, botón SOS
  utils/distance_calculator.dart           # Haversine + bearing + RSSI
android/app/src/main/AndroidManifest.xml   # permisos Android
ios/Runner/Info.plist                      # permisos iOS + Bonjour
```

---

## Arquitectura por capas

```
UI (screens, widgets)
    ↓ observa
GroupController (ChangeNotifier)
    ↓ usa
TransportService (interfaz)
    ↓ implementaciones
[FakeRelayTransport] [RelayTransport] [NearbyTransport]
```

El controller cifra/descifra **antes** de pasar bytes al transporte. El transporte mueve blobs opacos. Esto significa que el servidor relay (cuando exista) jamás ve contenido en claro — ni posiciones, ni mensajes, ni alertas SOS.

### Cifrado E2E (cómo funciona realmente)

1. El usuario crea un grupo. Se genera un código aleatorio tipo `FMO-482KL3` con `Random.secure()` (~45 bits de entropía, suficiente para resistir adivinanza online).
2. El código se mete por **Argon2id** (19 MiB / 2 iteraciones) con un salt determinista derivado del propio código. Esto da una clave simétrica de 32 bytes.
3. Esa clave **nunca se persiste**. Solo vive en memoria mientras la app está abierta. Cuando la app vuelve, se rederiva del código (que sí se guarda).
4. Cada mensaje se cifra con **XChaCha20-Poly1305** (nonce 24 bytes aleatorio + tag 16 bytes). El nonce de 24 bytes elimina cualquier preocupación realista de colisión.
5. El servidor relay solo retransmite blobs base64 que para él son ruido. Si lo capturan, no se puede descifrar sin el código.

Para verificar visualmente que dos celulares derivaron la misma clave, `Settings → Cifrado end-to-end` muestra una huella corta de 4 bytes hex. Si coincide en los dos, ambos ven los mismos mensajes.

### Por qué los ghosts no van cifrados

Los miembros simulados del modo dev publican blobs con prefijo `__GHOST__:`. El `GroupController` los detecta por el prefijo y los integra como peers normales sin pasar por descifrado. Así puedes ver el radar funcionando antes de tener un segundo dispositivo. En producción este código es completamente inerte — ningún transporte real produce blobs con ese prefijo.

---

## Migrar a un backend real

`RelayTransport` (lib/services/transport/relay/relay_transport.dart) está vacío a propósito. Cuando elijas backend, lo llenas y cambias **una sola línea** en `main.dart`.

### Opción A: Firebase Firestore

```yaml
# pubspec.yaml
dependencies:
  firebase_core: ^3.0.0
  cloud_firestore: ^5.0.0
```

```dart
// lib/services/transport/relay/relay_transport.dart
@override
Future<void> start({required String groupCode, required String selfId}) async {
  _selfId = selfId;
  _setState(TransportState.connecting);
  final col = FirebaseFirestore.instance
    .collection('groups').doc(groupCode).collection('messages');
  _sub = col
    .orderBy('ts', descending: true)
    .limit(50)
    .snapshots()
    .listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final data = ch.doc.data()!;
          if (data['from'] != _selfId) {
            _incomingCtrl.add(data['blob'] as String);
          }
        }
      }
    });
  _setState(TransportState.connected);
}

@override
Future<void> send(String blob) async {
  await FirebaseFirestore.instance
    .collection('groups').doc(_groupCode!).collection('messages')
    .add({'from': _selfId, 'blob': blob, 'ts': FieldValue.serverTimestamp()});
}
```

Reglas de Firestore para que cualquier usuario autenticado anónimamente pueda leer/escribir solo en grupos cuyo código conozca (la propia security model del grupo es el código en sí, ya que sin él no se descifra nada):

```
match /groups/{groupId}/messages/{msg} {
  allow read, create: if request.auth != null;
}
```

### Opción B: Supabase Realtime

```dart
final channel = Supabase.instance.client.channel('group:$groupCode');
channel.onBroadcast(event: 'msg', callback: (payload) {
  if (payload['from'] != selfId) _incomingCtrl.add(payload['blob']);
});
await channel.subscribe();
```

### Opción C: WebSocket propio

Un servidor mínimo en Node/Go/Rust que reciba `{type:"msg", group, from, blob}` y haga broadcast al resto del canal. Como el contenido viene cifrado, el servidor no necesita autenticar contenido — solo evitar abuso (rate limit por IP, tamaño máximo del blob).

### Composición relay + nearby

Para tener "cae automáticamente a P2P si se va internet", crea un `HybridTransport` que envuelva los dos:

```dart
class HybridTransport implements TransportService {
  final RelayTransport relay;
  final NearbyTransport nearby;
  // Envía por ambos; ignora duplicados al recibir vía id de mensaje.
}
```

Importante: como cada `TransportMessage` lleva su id propio (chat) o se trata como idempotente (heartbeat de posición), recibir el mismo mensaje por dos caminos es seguro — el `GroupController` desduplicará en `_onChatMessage` y los heartbeats simplemente se sobrescriben.

---

## Limitaciones conocidas (honestas)

- **iOS ↔ Android sin internet no funciona.** Google Nearby Connections (Android) y Apple MultipeerConnectivity (iOS) son APIs incompatibles. Si dos celulares de plataformas distintas pierden internet a la vez, no se ven entre sí. Solo funciona dentro de la misma plataforma. Esta es una limitación real del ecosistema móvil, no del código.
- **RSSI BLE entre celulares es ruidoso.** Útil hasta ~15 m con error de ±5 m. Por eso priorizamos GPS y solo usamos RSSI como fallback. No esperes precisión militar.
- **GPS en festivales puede ser muy malo.** Cuerpos, paredes, falta de cielo abierto suben el error a 10–30 m. La UI muestra siempre `±N m` para no engañar al usuario.
- **Brújula sin calibrar apunta mal.** El usuario debe hacer el "8" la primera vez. La pantalla `CompassScreen` marca la flecha en gris cuando la precisión GPS supera 15 m, para no inducir a error.
- **El código del grupo es el secreto.** Si alguien lo intercepta (foto del QR, pantalla compartida), tiene acceso completo. No hay rotación de claves. Para festivales con grupos pequeños y temporales esto es razonable; para amenazas más serias habría que agregar handshake Diffie-Hellman por miembro.

---

## Reciclado del proyecto original

| De `buscabeacon` | Adónde fue |
|---|---|
| `radial_map_widget.dart` | reescrito como `widgets/radar_widget.dart` |
| `RssiCalculator.calculateDistance` | `utils/distance_calculator.dart` (`rssiDistance`) con n=2.5 |
| Streams de `BluetoothService` | patrón replicado en `TransportService` |
| Sistema de permisos | `services/location/location_service.dart` |
| `BluetoothDevice`, `BeaconDevice` | reemplazados por `Member` con `Position` |
| `BeaconConfig` (MAC `C3:00:00:23:76:F2`) | eliminado, ya no aplica |

---

## TODO razonable de aquí en adelante

1. Implementar `RelayTransport` cuando elijas backend (sección "Migrar a backend real").
2. Persistir grupos en Hive con `services/storage/group_storage.dart` (carpeta creada, archivo aún no — fácil agregar).
3. Notificación push para SOS cuando la app está cerrada (Firebase Cloud Messaging si elegiste Firebase).
4. Compartir ubicación con un solo miembro (DM) en vez de todo el grupo.
5. Modo "norte arriba" vs "rumbo arriba" en el radar (hoy es solo norte arriba).
