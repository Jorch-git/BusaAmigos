import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../crypto/group_crypto.dart';

/// Resultado de codificar un payload, con métricas para el log de eventos.
class EncodedPayload {
  /// Blob cifrado base64 listo para el transporte.
  final String blob;

  /// Tamaño del JSON original (bytes).
  final int rawBytes;

  /// Tamaño tras comprimir (bytes). Igual a [rawBytes] si no se comprimió.
  final int compressedBytes;

  /// Tamaño final del blob cifrado en el cable (bytes del base64).
  final int wireBytes;

  final bool wasCompressed;

  const EncodedPayload({
    required this.blob,
    required this.rawBytes,
    required this.compressedBytes,
    required this.wireBytes,
    required this.wasCompressed,
  });

  /// Ratio de compresión del cuerpo (sin contar overhead de cifrado/base64).
  double get ratio => rawBytes == 0 ? 1 : compressedBytes / rawBytes;
}

/// Capa entre el [GroupController] y el [GroupCrypto] que:
///   1. Serializa el mapa a JSON.
///   2. Lo comprime con gzip si eso reduce el tamaño (y la config lo permite).
///   3. Antepone 1 byte de cabecera con flags (versión + comprimido).
///   4. Cifra todo con XChaCha20-Poly1305.
///
/// El receptor invierte el proceso: descifra, lee la cabecera, descomprime si
/// hace falta y parsea el JSON. Así el contenido viaja **comprimido y cifrado**
/// (minimiza datos), pero el [GroupController] sigue trabajando con mapas.
///
/// Nota: gzip vive en `dart:io`, disponible en Android/iOS (no en Flutter web,
/// que esta app no usa).
class PayloadCodec {
  final GroupCrypto crypto;

  /// Comprimir solo si el cuerpo supera este umbral; debajo, el overhead de
  /// gzip no compensa.
  final int minCompressBytes;

  PayloadCodec(this.crypto, {this.minCompressBytes = 64});

  static const int _version = 1;
  static const int _flagCompressed = 0x01;

  static final GZipCodec _gzip = GZipCodec(level: 6);

  /// Codifica un mapa. [forceCompress] = null deja decidir por tamaño.
  Future<EncodedPayload> encode(
    Map<String, dynamic> payload, {
    bool? forceCompress,
  }) async {
    final raw = utf8.encode(jsonEncode(payload));
    final shouldTry = forceCompress ?? raw.length >= minCompressBytes;

    List<int> body = raw;
    var compressed = false;
    if (shouldTry) {
      final gz = _gzip.encode(raw);
      // Solo vale la pena si de verdad quedó más chico.
      if (gz.length < raw.length) {
        body = gz;
        compressed = true;
      }
    }

    final header = (_version << 1) | (compressed ? _flagCompressed : 0);
    final framed = Uint8List(body.length + 1)
      ..[0] = header
      ..setRange(1, body.length + 1, body);

    final blob = await crypto.encryptBytes(framed);

    return EncodedPayload(
      blob: blob,
      rawBytes: raw.length,
      compressedBytes: body.length,
      wireBytes: blob.length,
      wasCompressed: compressed,
    );
  }

  /// Decodifica un blob a mapa. Devuelve `null` si falla el descifrado o el
  /// parseo (clave incorrecta, mensaje corrupto, formato desconocido).
  Future<Map<String, dynamic>?> decode(String blob) async {
    final framed = await crypto.decryptBytes(blob);
    if (framed == null || framed.isEmpty) return null;

    final header = framed[0];
    final compressed = (header & _flagCompressed) != 0;
    final body = framed.sublist(1);

    try {
      final jsonBytes = compressed ? _gzip.decode(body) : body;
      return jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
