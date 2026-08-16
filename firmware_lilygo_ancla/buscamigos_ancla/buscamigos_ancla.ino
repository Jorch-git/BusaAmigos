/*
 * ============================================================================
 *  BUSCAMIGOS — FIRMWARE DEL ANCLA  (LilyGo / ESP32)
 * ============================================================================
 *
 *  Qué hace este dispositivo:
 *    1. Levanta un punto de acceso WiFi al que se conectan los celulares.
 *    2. Corre un servidor WebSocket que RETRANSMITE lo que recibe de un
 *       celular a todos los demás del mismo canal.
 *    3. Guarda los últimos mensajes y se los reenvía a quien llegue tarde
 *       (store & forward).
 *    4. Si hay más anclas, se pasan los mensajes entre ellas por ESP-NOW.
 *    5. Publica su posición fija (GPS promediado o fijada a mano).
 *
 *  Principio de diseño: EL ANCLA ES TONTA.
 *    - No descifra nada. Los mensajes llegan cifrados extremo a extremo y se
 *      reenvían tal cual. El firmware no tiene criptografía.
 *    - No tiene tablas de ruteo. Difunde y ya.
 *    - Si el ancla se apaga, la app sigue funcionando con su malla P2P.
 *
 *  FUNCIONA CON UNA SOLA ANCLA. Las demás son opcionales: si hay más,
 *  se encuentran solas por ESP-NOW sin configuración adicional.
 *
 * ----------------------------------------------------------------------------
 *  LIBRERÍAS NECESARIAS (Arduino IDE → Gestor de librerías)
 *    · "WebSockets" de Markus Sattler        (arduinoWebSockets)
 *    · "TinyGPSPlus" de Mikal Hart           (solo si USAR_GPS = 1)
 *  El resto viene con el core de ESP32.
 *
 *  PLACA: cualquier ESP32 (LilyGo T-Beam, T-SIM7000G, T-Display, DevKit...)
 * ============================================================================
 */

#include <WiFi.h>
#include <WebServer.h>
#include <WebSocketsServer.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <Preferences.h>

// ============================================================================
//  CONFIGURACIÓN — lo único que necesitas tocar
// ============================================================================

// --- Identidad del ancla. CAMBIA EL NÚMERO EN CADA UNA (01, 02, 03...) ---
#define ANCLA_ID        1
#define ANCLA_NOMBRE    "Escenario"          // nombre legible para la app

// --- WiFi ---
// El SSID debe empezar con "buscamigos-ancla" para que la app lo reconozca.
#define AP_SSID_PREFIJO "buscamigos-ancla-"
#define AP_PASSWORD     "buscamigos"          // mínimo 8 caracteres, o "" = abierta
// TODAS las anclas deben usar el MISMO canal: ESP-NOW solo funciona entre
// dispositivos en el mismo canal. Usa 1, 6 u 11 (no se solapan entre sí).
#define AP_CANAL        6
#define MAX_CLIENTES    10                    // celulares simultáneos

// --- Posición fija del ancla ---
// 0 = usar las coordenadas escritas aquí abajo (RECOMENDADO: más preciso)
// 1 = promediar el GPS al encender y guardarlo (requiere módulo GPS)
#define USAR_GPS        0
#define POS_LAT         19.404400             // grados decimales
#define POS_LON         -99.097500
#define POS_ALT         2240.0                // metros sobre el nivel del mar

// --- Puente entre anclas (ESP-NOW). 1 = activado ---
#define USAR_ESPNOW     1
#define ESPNOW_TTL      3                     // saltos máximos entre anclas

// --- Buffer de mensajes guardados para quien llega tarde ---
#define BUFFER_MENSAJES 60                    // cuántos mensajes conservar
#define BUFFER_MINUTOS  10                    // por cuánto tiempo
#define MAX_MSG_BYTES   1024                  // tamaño máximo de un mensaje

// --- Pines del GPS (solo si USAR_GPS = 1). Ajusta a tu placa LilyGo. ---
#if USAR_GPS
  #include <TinyGPS++.h>
  #define GPS_RX_PIN    34
  #define GPS_TX_PIN    12
  #define GPS_BAUD      9600
  #define GPS_MUESTRAS  120                   // lecturas a promediar (~2 min)
  TinyGPSPlus gps;
  HardwareSerial gpsSerial(1);
#endif

// ============================================================================
//  ESTADO INTERNO — de aquí para abajo normalmente no se toca
// ============================================================================

WebServer http(80);
WebSocketsServer ws(8080);
Preferences prefs;

double anclaLat = POS_LAT, anclaLon = POS_LON, anclaAlt = POS_ALT;
bool   posicionFijada = false;

// Canal (grupo) al que pertenece cada cliente WebSocket conectado.
String canalDeCliente[MAX_CLIENTES];

// --- Buffer circular de mensajes para store & forward ---
struct MensajeGuardado {
  String   canal;
  String   texto;
  uint32_t id;
  uint32_t tsMs;
};
MensajeGuardado buffer[BUFFER_MENSAJES];
int bufferEscritura = 0;
int bufferUsados    = 0;

// --- Deduplicación: ids recientes ya vistos ---
#define DEDUPE_TAM 96
uint32_t dedupe[DEDUPE_TAM];
int      dedupePos = 0;

// --- Estadísticas para diagnóstico ---
uint32_t statRecibidos = 0, statDifundidos = 0, statPuenteados = 0,
         statDuplicados = 0, statReenviados = 0;

// ============================================================================
//  UTILIDADES
// ============================================================================

/*
 * Hash FNV-1a de 32 bits. Lo usamos como identificador único del mensaje:
 * como cada mensaje va cifrado con un nonce distinto, dos mensajes iguales
 * en texto plano producen blobs distintos → el hash sirve de id sin que el
 * ancla tenga que entender el contenido ni cambiar el protocolo.
 */
uint32_t hashMensaje(const String& s) {
  uint32_t h = 2166136261UL;
  for (size_t i = 0; i < s.length(); i++) {
    h ^= (uint8_t)s[i];
    h *= 16777619UL;
  }
  return h;
}

bool yaVisto(uint32_t id) {
  for (int i = 0; i < DEDUPE_TAM; i++) {
    if (dedupe[i] == id) return true;
  }
  return false;
}

void marcarVisto(uint32_t id) {
  dedupe[dedupePos] = id;
  dedupePos = (dedupePos + 1) % DEDUPE_TAM;
}

void guardarEnBuffer(const String& canal, const String& texto, uint32_t id) {
  buffer[bufferEscritura] = { canal, texto, id, millis() };
  bufferEscritura = (bufferEscritura + 1) % BUFFER_MENSAJES;
  if (bufferUsados < BUFFER_MENSAJES) bufferUsados++;
}

String ssidDelAncla() {
  char buf[40];
  snprintf(buf, sizeof(buf), "%s%02d", AP_SSID_PREFIJO, ANCLA_ID);
  return String(buf);
}

// ============================================================================
//  ESP-NOW — puente entre anclas
// ============================================================================
//
//  ESP-NOW solo admite 250 bytes por paquete, así que partimos los mensajes
//  grandes en fragmentos y los rearmamos del otro lado. Se difunde a la
//  dirección broadcast: cualquier ancla en el mismo canal lo recibe, sin
//  necesidad de emparejarlas ni de configurar direcciones MAC.

#if USAR_ESPNOW

uint8_t BROADCAST[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};

#define ESPNOW_CABECERA 12
#define ESPNOW_CARGA    (250 - ESPNOW_CABECERA)

struct __attribute__((packed)) TramaEspNow {
  uint32_t msgId;      // id del mensaje completo (hash)
  uint8_t  total;      // cuántos fragmentos son
  uint8_t  indice;     // cuál fragmento es este
  uint8_t  ttl;        // saltos restantes entre anclas
  uint8_t  canalLen;   // longitud del nombre de canal (va al inicio de datos)
  uint16_t largoTotal; // bytes totales del mensaje completo
  uint16_t reservado;
  uint8_t  datos[ESPNOW_CARGA];
};

// Rearmado de fragmentos entrantes
#define REARMADOS_MAX 4
struct Rearmado {
  uint32_t msgId;
  uint16_t largoTotal;
  uint8_t  total, recibidos, ttl, canalLen;
  uint32_t tsMs;
  char     datos[MAX_MSG_BYTES + 64];
  bool     tengo[16];
  bool     activo;
};
Rearmado rearmados[REARMADOS_MAX];

void difundirPorEspNow(const String& canal, const String& texto,
                       uint32_t id, uint8_t ttl) {
  if (ttl == 0) return;
  String payload = canal + texto;        // canal primero, luego el mensaje
  int largo = payload.length();
  if (largo > MAX_MSG_BYTES) return;
  int total = (largo + ESPNOW_CARGA - 1) / ESPNOW_CARGA;
  if (total > 16) return;                // límite de fragmentos

  for (int i = 0; i < total; i++) {
    TramaEspNow t = {};
    t.msgId      = id;
    t.total      = total;
    t.indice     = i;
    t.ttl        = ttl;
    t.canalLen   = canal.length();
    t.largoTotal = largo;
    int off = i * ESPNOW_CARGA;
    int n   = min((int)ESPNOW_CARGA, largo - off);
    memcpy(t.datos, payload.c_str() + off, n);
    esp_now_send(BROADCAST, (uint8_t*)&t, ESPNOW_CABECERA + n);
    delay(2);                            // respiro para no saturar la radio
  }
  statPuenteados++;
}

void difundirAClientes(const String& canal, const String& texto, int excepto);

void onEspNowRecv(const esp_now_recv_info_t* info, const uint8_t* data, int len) {
  if (len < ESPNOW_CABECERA) return;
  TramaEspNow t;
  memcpy(&t, data, min((size_t)len, sizeof(t)));
  int nDatos = len - ESPNOW_CABECERA;

  if (yaVisto(t.msgId)) { statDuplicados++; return; }

  // Buscar (o abrir) un rearmado para este mensaje
  int slot = -1;
  for (int i = 0; i < REARMADOS_MAX; i++) {
    if (rearmados[i].activo && rearmados[i].msgId == t.msgId) { slot = i; break; }
  }
  if (slot < 0) {
    for (int i = 0; i < REARMADOS_MAX; i++) {
      // libre, o caducado (más de 5 s sin completarse)
      if (!rearmados[i].activo || millis() - rearmados[i].tsMs > 5000) {
        slot = i;
        rearmados[i] = {};
        rearmados[i].activo     = true;
        rearmados[i].msgId      = t.msgId;
        rearmados[i].total      = t.total;
        rearmados[i].largoTotal = t.largoTotal;
        rearmados[i].ttl        = t.ttl;
        rearmados[i].canalLen   = t.canalLen;
        rearmados[i].tsMs       = millis();
        break;
      }
    }
  }
  if (slot < 0) return;                  // sin espacio: descartamos

  Rearmado& r = rearmados[slot];
  if (t.indice < 16 && !r.tengo[t.indice]) {
    int off = t.indice * ESPNOW_CARGA;
    if (off + nDatos <= (int)sizeof(r.datos)) {
      memcpy(r.datos + off, t.datos, nDatos);
      r.tengo[t.indice] = true;
      r.recibidos++;
    }
  }
  if (r.recibidos < r.total) return;      // aún faltan fragmentos

  // Mensaje completo: separar canal y contenido
  r.activo = false;
  marcarVisto(r.msgId);
  String completo = String();
  completo.reserve(r.largoTotal + 1);
  for (int i = 0; i < r.largoTotal; i++) completo += r.datos[i];
  String canal = completo.substring(0, r.canalLen);
  String texto = completo.substring(r.canalLen);

  guardarEnBuffer(canal, texto, r.msgId);
  difundirAClientes(canal, texto, -1);    // a los celulares de ESTA ancla
  statReenviados++;

  // Seguir propagando a otras anclas si le queda TTL
  if (r.ttl > 1) difundirPorEspNow(canal, texto, r.msgId, r.ttl - 1);
}

void iniciarEspNow() {
  if (esp_now_init() != ESP_OK) {
    Serial.println("[ESPNOW] error al iniciar");
    return;
  }
  esp_now_register_recv_cb(onEspNowRecv);
  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, BROADCAST, 6);
  peer.channel = AP_CANAL;
  peer.encrypt = false;
  esp_now_add_peer(&peer);
  Serial.printf("[ESPNOW] puente activo en canal %d\n", AP_CANAL);
}

#endif // USAR_ESPNOW

// ============================================================================
//  WEBSOCKET — el relay para los celulares
// ============================================================================

void difundirAClientes(const String& canal, const String& texto, int excepto) {
  int enviados = 0;
  for (int i = 0; i < MAX_CLIENTES; i++) {
    if (i == excepto) continue;
    if (canalDeCliente[i].length() == 0) continue;
    if (canalDeCliente[i] != canal) continue;
    ws.sendTXT(i, texto);
    enviados++;
  }
  if (enviados) statDifundidos += enviados;
}

/*
 * Al conectarse un celular, le mandamos lo que se perdió mientras no estaba.
 * Esto es el "store & forward": si te quedaste sin cobertura un minuto, al
 * volver recibes los mensajes de ese minuto en vez de perderlos.
 */
void reenviarPendientes(int cliente, const String& canal) {
  uint32_t limite = (uint32_t)BUFFER_MINUTOS * 60000UL;
  uint32_t ahora  = millis();
  int n = 0;
  for (int k = 0; k < bufferUsados; k++) {
    int idx = (bufferEscritura - bufferUsados + k + BUFFER_MENSAJES * 2) % BUFFER_MENSAJES;
    if (buffer[idx].canal != canal) continue;
    if (ahora - buffer[idx].tsMs > limite) continue;
    ws.sendTXT(cliente, buffer[idx].texto);
    n++;
    delay(3);                             // no atragantar al cliente
  }
  if (n) Serial.printf("[WS] cliente %d recibió %d mensajes pendientes\n", cliente, n);
}

/*
 * El canal viene en la URL: /ws?c=<canal>
 * IMPORTANTE: el canal NO es el código del grupo, es un hash del código.
 * Así el ancla puede agrupar a los miembros sin poder derivar jamás la clave
 * de cifrado (que se obtiene del código con Argon2id en la app).
 */
String canalDesdeUrl(const String& url) {
  int p = url.indexOf("c=");
  if (p < 0) return "default";
  String c = url.substring(p + 2);
  int amp = c.indexOf('&');
  if (amp >= 0) c = c.substring(0, amp);
  c.trim();
  return c.length() ? c : "default";
}

void onWsEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length) {
  if (num >= MAX_CLIENTES) return;

  switch (type) {
    case WStype_CONNECTED: {
      String url = String((char*)payload);
      String canal = canalDesdeUrl(url);
      canalDeCliente[num] = canal;
      Serial.printf("[WS] cliente %d conectado, canal=%s\n", num, canal.c_str());
      reenviarPendientes(num, canal);
      break;
    }

    case WStype_DISCONNECTED:
      Serial.printf("[WS] cliente %d desconectado\n", num);
      canalDeCliente[num] = "";
      break;

    case WStype_TEXT: {
      if (length == 0 || length > MAX_MSG_BYTES) break;
      String texto;
      texto.reserve(length + 1);
      for (size_t i = 0; i < length; i++) texto += (char)payload[i];

      String canal = canalDeCliente[num];
      if (canal.length() == 0) canal = "default";

      uint32_t id = hashMensaje(texto);
      if (yaVisto(id)) { statDuplicados++; break; }
      marcarVisto(id);
      statRecibidos++;

      // 1) guardar para los que lleguen después
      guardarEnBuffer(canal, texto, id);
      // 2) repartir a los demás celulares de esta ancla
      difundirAClientes(canal, texto, num);
      // 3) pasarlo a las otras anclas
      #if USAR_ESPNOW
        difundirPorEspNow(canal, texto, id, ESPNOW_TTL);
      #endif
      break;
    }

    default:
      break;
  }
}

// ============================================================================
//  HTTP — descubrimiento y diagnóstico
// ============================================================================

int clientesConectados() {
  int n = 0;
  for (int i = 0; i < MAX_CLIENTES; i++) if (canalDeCliente[i].length()) n++;
  return n;
}

/*
 * /info es como la app descubre que hay un ancla y obtiene su posición.
 */
void handleInfo() {
  char json[420];
  snprintf(json, sizeof(json),
    "{\"ancla\":true,\"id\":%d,\"nombre\":\"%s\",\"ssid\":\"%s\","
    "\"lat\":%.6f,\"lon\":%.6f,\"alt\":%.1f,\"posFijada\":%s,"
    "\"ws\":8080,\"canalWifi\":%d,\"clientes\":%d,"
    "\"recibidos\":%u,\"difundidos\":%u,\"puenteados\":%u,"
    "\"reenviados\":%u,\"duplicados\":%u,\"uptimeS\":%lu}",
    ANCLA_ID, ANCLA_NOMBRE, ssidDelAncla().c_str(),
    anclaLat, anclaLon, anclaAlt, posicionFijada ? "true" : "false",
    AP_CANAL, clientesConectados(),
    statRecibidos, statDifundidos, statPuenteados,
    statReenviados, statDuplicados, millis() / 1000);

  http.sendHeader("Access-Control-Allow-Origin", "*");
  http.send(200, "application/json", json);
}

/*
 * Android comprueba si una WiFi "tiene internet" pidiendo /generate_204.
 * Si no responde, Android puede DESCARTAR esta red y volver a datos móviles,
 * dejando al ancla incomunicada. Respondiendo 204 evitamos ese problema.
 * Es el detalle práctico que más dolores de cabeza ahorra.
 */
void handle204() { http.send(204, "text/plain", ""); }

void handleRaiz() {
  String h = "<html><meta name=viewport content='width=device-width'>"
             "<body style='font-family:sans-serif;background:#111;color:#eee;padding:24px'>"
             "<h2 style='color:#1DD27D'>Buscamigos — Ancla " + String(ANCLA_ID) + "</h2>"
             "<p>" + String(ANCLA_NOMBRE) + "</p>"
             "<p>Clientes conectados: <b>" + String(clientesConectados()) + "</b></p>"
             "<p>Posición: " + String(anclaLat, 6) + ", " + String(anclaLon, 6) + "</p>"
             "<p><a style='color:#1DD27D' href='/info'>/info (JSON)</a></p>"
             "</body></html>";
  http.send(200, "text/html", h);
}

// ============================================================================
//  GPS — fijar la posición al encender (opcional)
// ============================================================================

#if USAR_GPS
/*
 * El ancla no se mueve, así que promediar muchas lecturas da una posición
 * bastante mejor que la de un celular. Se guarda en memoria no volátil para
 * no repetir el proceso en cada arranque.
 */
void fijarPosicionConGps() {
  prefs.begin("ancla", false);
  if (prefs.getBool("posOk", false)) {
    anclaLat = prefs.getDouble("lat", POS_LAT);
    anclaLon = prefs.getDouble("lon", POS_LON);
    anclaAlt = prefs.getDouble("alt", POS_ALT);
    posicionFijada = true;
    prefs.end();
    Serial.printf("[GPS] posición recuperada: %.6f, %.6f\n", anclaLat, anclaLon);
    return;
  }

  gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  Serial.println("[GPS] promediando posición, espera...");
  double sLat = 0, sLon = 0, sAlt = 0;
  int n = 0;
  uint32_t t0 = millis();

  while (n < GPS_MUESTRAS && millis() - t0 < 300000UL) {   // máx 5 min
    while (gpsSerial.available()) gps.encode(gpsSerial.read());
    if (gps.location.isUpdated() && gps.location.isValid() &&
        gps.hdop.isValid() && gps.hdop.hdop() < 3.0) {     // descarta mala calidad
      sLat += gps.location.lat();
      sLon += gps.location.lng();
      sAlt += gps.altitude.meters();
      n++;
      if (n % 10 == 0) Serial.printf("[GPS] %d/%d muestras\n", n, GPS_MUESTRAS);
    }
    delay(10);
  }

  if (n >= 10) {
    anclaLat = sLat / n;  anclaLon = sLon / n;  anclaAlt = sAlt / n;
    posicionFijada = true;
    prefs.putDouble("lat", anclaLat);
    prefs.putDouble("lon", anclaLon);
    prefs.putDouble("alt", anclaAlt);
    prefs.putBool("posOk", true);
    Serial.printf("[GPS] fijada con %d muestras: %.6f, %.6f, %.1f m\n",
                  n, anclaLat, anclaLon, anclaAlt);
  } else {
    Serial.println("[GPS] sin fix suficiente, uso las coordenadas del código");
  }
  prefs.end();
}
#endif

// ============================================================================
//  ARRANQUE
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(400);
  Serial.println("\n===== BUSCAMIGOS — ANCLA =====");
  Serial.printf("Ancla %d (%s)\n", ANCLA_ID, ANCLA_NOMBRE);

#if USAR_GPS
  fijarPosicionConGps();
#else
  posicionFijada = true;      // coordenadas fijadas a mano en la configuración
  Serial.printf("Posición manual: %.6f, %.6f, %.1f m\n", anclaLat, anclaLon, anclaAlt);
#endif

  // --- Punto de acceso WiFi ---
  WiFi.mode(WIFI_AP);
  String ssid = ssidDelAncla();
  bool ok = WiFi.softAP(ssid.c_str(),
                        strlen(AP_PASSWORD) >= 8 ? AP_PASSWORD : NULL,
                        AP_CANAL, 0, MAX_CLIENTES);
  Serial.printf("[WiFi] AP \"%s\" %s · IP %s · canal %d\n",
                ssid.c_str(), ok ? "OK" : "FALLÓ",
                WiFi.softAPIP().toString().c_str(), AP_CANAL);

  // ESP-NOW exige que el canal esté fijado explícitamente.
  esp_wifi_set_channel(AP_CANAL, WIFI_SECOND_CHAN_NONE);

#if USAR_ESPNOW
  iniciarEspNow();
#endif

  // --- Servidor HTTP ---
  http.on("/",             handleRaiz);
  http.on("/info",         handleInfo);
  http.on("/generate_204", handle204);   // Android
  http.on("/gen_204",      handle204);   // Android (variante)
  http.onNotFound(handle204);            // cualquier otra cosa: 204
  http.begin();

  // --- Servidor WebSocket ---
  ws.begin();
  ws.onEvent(onWsEvent);

  Serial.println("[LISTO] esperando celulares...");
  Serial.printf("        conéctate a la WiFi \"%s\" y abre http://%s/\n",
                ssid.c_str(), WiFi.softAPIP().toString().c_str());
}

void loop() {
  ws.loop();
  http.handleClient();

  // Latido cada 30 s para saber que sigue vivo
  static uint32_t ultimo = 0;
  if (millis() - ultimo > 30000) {
    ultimo = millis();
    Serial.printf("[VIVO] clientes=%d recibidos=%u difundidos=%u "
                  "puenteados=%u reenviados=%u\n",
                  clientesConectados(), statRecibidos, statDifundidos,
                  statPuenteados, statReenviados);
  }
}
