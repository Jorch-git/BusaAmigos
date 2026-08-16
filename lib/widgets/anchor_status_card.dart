import 'dart:async';

import 'package:flutter/material.dart';

import '../services/transport/anchor/anchor_relay_transport.dart';

/// Tarjeta para la pantalla de Consola: muestra si hay un ancla LilyGo
/// conectada, cuál es y cuántos mensajes han pasado por ella.
///
/// Uso: pásale la instancia de [AnchorRelayTransport] que creaste en main.dart.
///
///   AnchorStatusCard(anchor: miAncla)
class AnchorStatusCard extends StatefulWidget {
  final AnchorRelayTransport anchor;

  const AnchorStatusCard({super.key, required this.anchor});

  @override
  State<AnchorStatusCard> createState() => _AnchorStatusCardState();
}

class _AnchorStatusCardState extends State<AnchorStatusCard> {
  StreamSubscription? _sub;
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    _sub = widget.anchor.anchorStream.listen((_) {
      if (mounted) setState(() {});
    });
    _refresco = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _refresco?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.anchor.ancla;
    final hay = widget.anchor.hayAncla;
    const verde = Color(0xFF1DD27D);
    const azul = Color(0xFF378ADD);
    final muted = Theme.of(context).textTheme.bodySmall?.color ??
        const Color(0xFF6B7A73);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hay ? azul : muted.withValues(alpha: 0.3),
          width: hay ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hay ? Icons.router : Icons.router_outlined,
                  size: 18, color: hay ? azul : muted),
              const SizedBox(width: 8),
              Text(
                hay ? 'Ancla conectada' : 'Sin ancla · malla P2P',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: hay ? azul : muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hay
                ? 'Los mensajes viajan por el ancla y por la malla a la vez.'
                : 'Conéctate a la WiFi "buscamigos-ancla-XX" para reforzar '
                    'la red. Sin ancla la app funciona igual que siempre.',
            style: TextStyle(fontSize: 11, color: muted, height: 1.4),
          ),
          if (hay && a != null) ...[
            const SizedBox(height: 12),
            _fila('Ancla', '${a.nombre} (#${a.id})'),
            _fila('Dirección', a.host),
            _fila('Otros conectados', '${a.clientes}'),
            _fila('Posición',
                '${a.lat.toStringAsFixed(5)}, ${a.lon.toStringAsFixed(5)}'),
            _fila('Posición fijada', a.posicionFijada ? 'sí' : 'no'),
            const Divider(height: 20),
            _fila('Enviados por ancla', '${widget.anchor.enviados}'),
            _fila('Recibidos por ancla', '${widget.anchor.recibidos}'),
            _fila('Reconexiones', '${widget.anchor.reconexiones}'),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (hay ? azul : verde).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              hay
                  ? 'El ancla reenvía mensajes cifrados que no puede leer.'
                  : 'Buscando anclas cada 6 segundos…',
              style: TextStyle(
                  fontSize: 11,
                  color: hay ? azul : verde,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(String k, String v) {
    final muted = Theme.of(context).textTheme.bodySmall?.color ??
        const Color(0xFF6B7A73);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12, color: muted)),
          Text(v,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
