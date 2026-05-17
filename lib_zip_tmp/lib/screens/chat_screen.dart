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

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GroupController>();
    final group = controller.group;
    if (group == null) return const SizedBox();

    return Column(
      children: [
        _buildHeader(group.name, group.connectedCount),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: controller.messages.length,
            itemBuilder: (_, i) => _buildBubble(controller.messages[i]),
          ),
        ),
        _buildQuickChips(controller),
        _buildInput(controller),
      ],
    );
  }

  Widget _buildHeader(String name, int connected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.cardBg)),
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
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage m) {
    final align = m.fromSelf ? Alignment.centerRight : Alignment.centerLeft;
    final color = m.fromSelf ? const Color(0xFF378ADD) : AppTheme.cardBg;
    final br = m.fromSelf
        ? const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14))
        : const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            m.fromSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!m.fromSelf)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(m.senderName,
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11)),
            ),
          Align(
            alignment: align,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: color, borderRadius: br),
              child: Text(
                m.text,
                style: TextStyle(
                  color: m.fromSelf ? Colors.white : Colors.white,
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
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 10),
                ),
                if (m.fromSelf) ...[
                  const SizedBox(width: 4),
                  Icon(
                    m.delivered ? Icons.done_all : Icons.done,
                    size: 12,
                    color: m.delivered
                        ? AppTheme.accentGreen
                        : AppTheme.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChips(GroupController controller) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.cardBg)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kQuickMessages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final text = kQuickMessages[i];
          return Center(
            child: GestureDetector(
              onTap: () => controller.sendChat(text),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
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

  Widget _buildInput(GroupController controller) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12, right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        top: 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                hintText: 'Escribe un mensaje',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: AppTheme.accentGreen),
            onPressed: () {
              final text = _ctrl.text.trim();
              if (text.isEmpty) return;
              controller.sendChat(text);
              _ctrl.clear();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollCtrl.hasClients) {
                  _scrollCtrl.animateTo(
                    _scrollCtrl.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              });
            },
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
