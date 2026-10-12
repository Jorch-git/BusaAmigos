# Copia local de flutter_nearby_connections_plus 1.2.2

Origen: https://pub.dev/packages/flutter_nearby_connections_plus (1.2.2, jul 2025)
Repositorio: https://github.com/edgarladeira/flutter_nearby_connections_plus

Se trae al proyecto porque la versión publicada no compila con Flutter 3.29+
(usa `PluginRegistry.Registrar`, que Flutter eliminó). Hasta oct 2026 el parche
vivía solo en la caché de pub de C: (editado a mano el 10 may 2026), por eso el
proyecto únicamente compilaba en esa PC.

## Cambios respecto al original

1. `FlutterNearbyConnectionsPlugin.kt`: se quitó `registerWith(Registrar)` y su
   import (API v1 de Flutter, ya no existe).
2. `android/build.gradle`: sin `jcenter()` (se elimina en Gradle 9), con
   `namespace`, AGP 8.9.1 y Kotlin 2.1.0 como la app, Java 11.
3. `AndroidManifest.xml`: sin atributo `package` (lo reemplaza `namespace`) y
   `android.hardware.wifi.direct` como `required="false"`.
4. Se omitieron `example/`, `test/` y los GIF del README.

## Pendiente (Fase 1 del diagnóstico)

- `stopAdvertisingPeer()` / `stopBrowsingForPeers()` destruyen el servicio del plugin.
- `onDetachedFromEngine` llama `exitProcess(0)`.
- `SERVICE_ID` fijo en Android ("flutter_nearby_connections").
- `requestConnection` sin listener de fallo.
