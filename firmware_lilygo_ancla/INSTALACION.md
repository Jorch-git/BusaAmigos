# Buscamigos — Anclas LilyGo: instalación

Dos partes independientes: el **firmware** del ESP32 y el **cableado en la app**.
La app funciona con o sin anclas, así que puedes hacer primero una y luego la otra.

---

## PARTE 1 — Firmware del ancla

### 1.1 Librerías

En Arduino IDE → *Herramientas → Administrar bibliotecas*, instala:

- **WebSockets** de Markus Sattler (busca `arduinoWebSockets`)
- **TinyGPSPlus** de Mikal Hart — *solo si vas a usar el GPS*

El resto (WiFi, ESP-NOW, WebServer, Preferences) viene con el core de ESP32.

### 1.2 Configurar cada ancla

Abre `buscamigos_ancla.ino` y toca solo el bloque de configuración de arriba:

```cpp
#define ANCLA_ID        1              // ← 1, 2, 3... DISTINTO EN CADA ANCLA
#define ANCLA_NOMBRE    "Escenario"    // nombre que verás en la app

#define AP_CANAL        6              // ← EL MISMO EN TODAS LAS ANCLAS
#define AP_PASSWORD     "buscamigos"   // mínimo 8 caracteres

#define USAR_GPS        0              // 0 = coordenadas a mano (recomendado)
#define POS_LAT         19.404400      // ← la posición real del ancla
#define POS_LON         -99.097500
#define POS_ALT         2240.0
```

**Lo único crítico:** `ANCLA_ID` debe ser distinto en cada una, y `AP_CANAL`
debe ser **el mismo en todas**. ESP-NOW solo comunica anclas que estén en el
mismo canal WiFi — si pones canales distintos, no se verán entre sí.

### 1.3 Fijar la posición

**Manual (recomendado):** pon las coordenadas en `POS_LAT/POS_LON/POS_ALT`.
Es lo más preciso y no depende de que el GPS enganche.

**Automática:** pon `USAR_GPS 1` y ajusta los pines de tu placa. Al primer
arranque promedia ~120 lecturas (descartando las de mala calidad) y guarda el
resultado en memoria; en los siguientes arranques lo reutiliza. Como el ancla
no se mueve, ese promedio sale bastante mejor que el GPS de un celular.

### 1.4 Cargar y probar

1. Selecciona tu placa ESP32 y súbelo.
2. Abre el Monitor Serie a **115200**. Deberías ver:

```
===== BUSCAMIGOS — ANCLA =====
Ancla 1 (Escenario)
[WiFi] AP "buscamigos-ancla-01" OK · IP 192.168.4.1 · canal 6
[ESPNOW] puente activo en canal 6
[LISTO] esperando celulares...
```

3. Desde el celular, conéctate a la WiFi **`buscamigos-ancla-01`**
   (contraseña `buscamigos`) y abre `http://192.168.4.1/` en el navegador.
   Debe salir una página con el nombre del ancla y los clientes conectados.

Si ves esa página, el ancla está lista.

---

## PARTE 2 — Cableado en la app

### 2.1 Copiar los archivos nuevos

```
lib/utils/channel_id.dart
lib/services/transport/anchor/anchor_relay_transport.dart
lib/services/transport/composite/mesh_plus_anchor_transport.dart
lib/widgets/anchor_status_card.dart          (opcional, para diagnóstico)
```

**No se reemplaza ningún archivo tuyo.** No hay dependencias nuevas: usa
`http` (que ya tienes) y el WebSocket de `dart:io`.

### 2.2 Una edición en `main.dart`

Busca estas líneas (están alrededor de la línea 36):

```dart
final nearby = NearbyTransport();
final mesh = MeshTransport(nearby, profile: MeshProfile.highDensity);
final transport = HybridTransport(mesh /*, relay: relay*/);
```

Cámbialas por:

```dart
final nearby = NearbyTransport();
final mesh = MeshTransport(nearby, profile: MeshProfile.highDensity);
final ancla = AnchorRelayTransport();
final transport = MeshPlusAnchorTransport(mesh, ancla);
```

Y añade los dos imports arriba, junto a los demás de transporte:

```dart
import 'services/transport/anchor/anchor_relay_transport.dart';
import 'services/transport/composite/mesh_plus_anchor_transport.dart';
```

Eso es todo. `HybridTransport` se queda en el proyecto por si algún día
quieres el relay por internet; simplemente ya no se usa en el arranque.

### 2.3 Ver el estado (opcional pero muy útil para probar)

En `console_screen.dart`, guarda una referencia al ancla y añade la tarjeta.
Como `main.dart` ya crea la instancia, lo más simple es hacerla accesible:

```dart
// en main.dart, después de crear el ancla:
AnchorRelayTransport.instanciaActual = ancla;   // si añades ese campo estático
```

O más sencillo: pásala por el `MultiProvider` que ya usas y léela con
`context.read<AnchorRelayTransport>()`, luego:

```dart
AnchorStatusCard(anchor: miAncla)
```

---

## Cómo probarlo

### Prueba 1 — Una sola ancla
1. Enciende el ancla.
2. En **dos celulares**: conéctalos a la WiFi `buscamigos-ancla-01`.
3. Únete al mismo grupo en ambos.
4. Manda un mensaje de chat. Debe llegar **al instante**.
5. En el Monitor Serie verás `[WS] cliente 0 conectado` y los contadores subir.

### Prueba 2 — Store & forward
1. Con dos celulares conectados, **apaga la WiFi de uno**.
2. Manda dos o tres mensajes desde el otro.
3. Vuelve a conectar el primero al ancla.
4. Debe recibir los mensajes que se perdió (los guarda 10 minutos).

### Prueba 3 — Degradación (lo más importante)
1. **Apaga el ancla** con la app abierta y en un grupo.
2. La app debe seguir funcionando con la malla P2P, sin errores.
3. Vuelve a encender el ancla: la app la reencuentra sola en ~6 segundos.

### Prueba 4 — Dos anclas (puente ESP-NOW)
1. Programa una segunda con `ANCLA_ID 2` y **el mismo `AP_CANAL`**.
2. Celular A en `buscamigos-ancla-01`, celular B en `buscamigos-ancla-02`.
3. Manda un mensaje desde A: debe llegar a B pasando por el puente.
4. En el serie del ancla 2 verás subir `reenviados`.

---

## Detalles que conviene saber

**Android y la WiFi sin internet.** Android puede descartar una red que no
tiene internet y volver a datos móviles, dejando el ancla incomunicada. El
firmware responde `204` a `/generate_204` (la comprobación que hace Android)
justamente para evitarlo. Si aun así te da problemas en algún equipo, desactiva
los datos móviles mientras pruebas.

**El ancla nunca ve el código del grupo.** Se le manda un hash SHA-256 del
código (`ChannelId`), no el código. Como la clave de cifrado se deriva del
código con Argon2id, mandarlo en claro habría permitido al ancla descifrar
todo. Con el hash, el ancla agrupa a los miembros sin poder leer nada.

**Límite de ESP-NOW.** Cada paquete admite 250 bytes, así que el firmware parte
los mensajes grandes en fragmentos y los rearma del otro lado. Es transparente,
pero por eso hay un tope de `MAX_MSG_BYTES` (1024) por mensaje.

**Alimentación.** Un powerbank normal alcanza para toda una jornada. Si el
ancla se apaga, no pasa nada grave: los celulares vuelven solos a la malla P2P.

---

## Si algo no funciona

| Síntoma | Qué revisar |
|---|---|
| La app no encuentra el ancla | ¿El celular está conectado a la WiFi del ancla? Prueba `http://192.168.4.1/` en el navegador |
| Se conecta pero no llegan mensajes | ¿Los dos celulares están en el **mismo grupo**? El canal se deriva del código |
| Las dos anclas no se hablan | Casi siempre es el `AP_CANAL`: debe ser idéntico en ambas |
| Android se sale de la WiFi del ancla | Desactiva datos móviles, o revisa que `/generate_204` responda |
| Mensajes duplicados | No debería pasar: el compositor deduplica. Si ocurre, avísame con los contadores de la consola |
