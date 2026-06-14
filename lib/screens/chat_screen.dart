import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme/app_theme.dart';
import '../models/chat_message.dart';
import '../services/group_controller.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  /// Mensaje al que estamos respondiendo (si hay uno). Estilo WhatsApp:
  /// aparece una barra de cita encima del input.
  ChatMessage? _replyingTo;

  @override
  void initState() {
    super.initState();
    // Marcar el chat como abierto cuando se monta, para resetear el badge
    // y silenciar notificaciones mientras el usuario lo está viendo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GroupController>().setChatOpen(true);
    });
  }

  @override
  void dispose() {
    // Marcar como cerrado al salir.
    context.read<GroupController>().setChatOpen(false);
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send(GroupController controller) {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    controller.sendChat(text, replyTo: _replyingTo);
    _ctrl.clear();
    setState(() => _replyingTo = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final group = controller.group;
    if (group == null) return const SizedBox();

    // Asegurar que el badge quede en cero mientras el chat está visible.
    if (controller.unreadCount != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.markChatRead();
      });
    }

    return Column(
      children: [
        _buildHeader(context, group.name, group.connectedCount),
        Expanded(
          child: controller.messages.isEmpty
              ? _buildEmpty(context)
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: controller.messages.length,
                  itemBuilder: (_, i) =>
                      _buildBubble(context, controller.messages[i]),
                ),
        ),
        if (_replyingTo != null) _buildReplyPreview(context),
        _buildQuickChips(controller),
        _buildInput(context, controller),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 48, color: AppTheme.textMutedOf(context)),
          const SizedBox(height: 12),
          Text('Aún no hay mensajes',
              style: TextStyle(color: AppTheme.textMutedOf(context))),
          const SizedBox(height: 4),
          Text('Escribe algo para tu grupo',
              style: TextStyle(
                  color: AppTheme.textMutedOf(context), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String name, int connected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppTheme.cardBgOf(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.accentGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('$connected conectados',
                      style: TextStyle(
                          color: AppTheme.textMutedOf(context),
                          fontSize: 12)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(BuildContext context, ChatMessage m) {
    final align = m.fromSelf ? Alignment.centerRight : Alignment.centerLeft;
    final color = m.fromSelf ? const Color(0xFF378ADD) : AppTheme.cardBgOf(context);
    final textColor = m.fromSelf
        ? Colors.white
        : (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : const Color(0xFF1A1A1C));
    final br = m.fromSelf
        ? const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14))
        : const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14));

    // Dismissible para swipe-to-reply (estilo WhatsApp).
    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        setState(() => _replyingTo = m);
        return false; // No eliminar, solo activar respuesta.
      },
      background: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.reply, color: AppTheme.textMutedOf(context)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment:
              m.fromSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!m.fromSelf)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(m.senderName,
                    style: TextStyle(
                        color: AppTheme.textMutedOf(context), fontSize: 11)),
              ),
            Align(
              alignment: align,
              child: GestureDetector(
                onLongPress: () => setState(() => _replyingTo = m),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: color, borderRadius: br),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Cita del mensaje al que responde (si aplica).
                      if (m.isReply) _buildQuotedBlock(context, m, m.fromSelf),
                      Text(
                        m.text,
                        style: TextStyle(color: textColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hhmm(m.sentAt),
                    style: TextStyle(
                        color: AppTheme.textMutedOf(context), fontSize: 10),
                  ),
                  if (m.fromSelf) ...[
                    const SizedBox(width: 4),
                    Icon(
                      m.delivered ? Icons.done_all : Icons.done,
                      size: 12,
                      color: m.delivered
                          ? AppTheme.accentGreen
                          : AppTheme.textMutedOf(context),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bloque de cita dentro de una burbuja (el mensaje al que responde).
  Widget _buildQuotedBlock(BuildContext context, ChatMessage m, bool onSelfBubble) {
    final bg = onSelfBubble
        ? Colors.white.withValues(alpha: 0.18)
        : AppTheme.accentGreen.withValues(alpha: 0.12);
    final barColor =
        onSelfBubble ? Colors.white : AppTheme.accentGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: barColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            m.replyToSender ?? '',
            style: TextStyle(
              color: barColor,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            m.replyToText ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onSelfBubble
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppTheme.textMutedOf(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Barra de "respondiendo a…" encima del input.
  Widget _buildReplyPreview(BuildContext context) {
    final m = _replyingTo!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppTheme.cardBgOf(context),
        border: Border(
          left: const BorderSide(color: AppTheme.accentGreen, width: 4),
          top: BorderSide(color: AppTheme.scaffoldBgOf(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Respondiendo a ${m.fromSelf ? "ti" : m.senderName}',
                  style: const TextStyle(
                    color: AppTheme.accentGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  m.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTheme.textMutedOf(context), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChips(GroupController controller) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: AppTheme.cardBgOf(context))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kQuickMessages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final text = kQuickMessages[i];
          return Center(
            child: GestureDetector(
              onTap: () {
                controller.sendChat(text, replyTo: _replyingTo);
                setState(() => _replyingTo = null);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardBgOf(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(text, style: const TextStyle(fontSize: 12)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInput(BuildContext context, GroupController controller) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        top: 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(controller),
              decoration: const InputDecoration(
                hintText: 'Escribe un mensaje',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: AppTheme.accentGreen),
            onPressed: () => _send(controller),
          ),
        ],
      ),
    );
  }

  String _hhmm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
