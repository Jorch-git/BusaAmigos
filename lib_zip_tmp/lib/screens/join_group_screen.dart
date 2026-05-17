import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../services/crypto/group_code.dart';
import '../services/group_controller.dart';
import 'pending_verification_screen.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _codeCtrl = TextEditingController();
  final _myNameCtrl = TextEditingController();
  bool _joining = false;
  bool _scanning = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _myNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_joining) return;
    if (_myNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe tu nombre')),
      );
      return;
    }
    final code = _codeCtrl.text.trim();
    if (!GroupCode.isValid(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código no válido (formato XXX-XXXXXX)')),
      );
      return;
    }
    setState(() => _joining = true);
    try {
      // requireVerification: true (por defecto) → pasa por la pantalla
      // de espera hasta detectar a algún miembro existente.
      await context.read<GroupController>().joinGroup(
            code: code,
            myDisplayName: _myNameCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PendingVerificationScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unirse a grupo'),
        actions: [
          IconButton(
            icon: Icon(_scanning ? Icons.keyboard : Icons.qr_code_scanner),
            onPressed: () => setState(() => _scanning = !_scanning),
            tooltip: _scanning ? 'Teclear código' : 'Escanear QR',
          ),
        ],
      ),
      body: SafeArea(
        child: _scanning ? _buildScanner() : _buildForm(),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final raw = barcode.rawValue;
              if (raw != null && GroupCode.isValid(raw)) {
                setState(() {
                  _codeCtrl.text = GroupCode.normalize(raw);
                  _scanning = false;
                });
                return;
              }
            }
          },
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.accentGreen, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        const Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: Text(
            'Apunta al QR del organizador',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              shadows: [Shadow(blurRadius: 4)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Tu nombre', style: TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          TextField(controller: _myNameCtrl),
          const SizedBox(height: 20),
          const Text('Código del grupo',
              style: TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\-]')),
            ],
            decoration: const InputDecoration(hintText: 'FMO-482KL3'),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear QR'),
            onPressed: () => setState(() => _scanning = true),
          ),
          const SizedBox(height: 16),
          // Aviso explícito sobre la verificación física.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.accentGreen.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.location_on,
                    size: 16, color: AppTheme.accentGreen),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Necesitas estar cerca del organizador (≤30 m) para confirmar tu unión al grupo.',
                    style: TextStyle(
                        color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _joining ? null : _join,
            child: _joining
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2),
                  )
                : const Text('Unirme'),
          ),
        ],
      ),
    );
  }
}
