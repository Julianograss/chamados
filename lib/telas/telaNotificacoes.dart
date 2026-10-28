import 'package:flutter/material.dart';

import '../servicos/formatadores.dart';
import '../servicos/notificacao_service.dart';
import '../servicos/ticket_service.dart';
import '../tema.dart';

/// Central de notificações: histórico persistente, com lidas/por ler.
class telaNotificacoes extends StatefulWidget {
  const telaNotificacoes({super.key});

  @override
  State<telaNotificacoes> createState() => _telaNotificacoesState();
}

class _telaNotificacoesState extends State<telaNotificacoes> {
  late final Stream<List<Map<String, dynamic>>> _stream = NotificacaoService.instance.observar();

  static (IconData, Color) _icone(String? tipo) {
    switch (tipo) {
      case 'novo_chamado':
        return (Icons.inbox_outlined, const Color(0xFF2563EB));
      case 'atribuido':
      case 'assumido':
        return (Icons.assignment_ind_outlined, const Color(0xFF2563EB));
      case 'cliente_respondeu':
      case 'resposta':
        return (Icons.chat_bubble_outline, const Color(0xFF0891B2));
      case 'resolvido':
        return (Icons.check_circle_outline, const Color(0xFF059669));
      case 'reaberto':
        return (Icons.refresh, const Color(0xFFD97706));
      case 'pendente':
        return (Icons.pause_circle_outline, const Color(0xFF7C3AED));
      case 'sla_proximo':
        return (Icons.timer_outlined, const Color(0xFFD97706));
      case 'sla_vencido':
        return (Icons.local_fire_department, const Color(0xFFE11D48));
      default:
        return (Icons.notifications_none, const Color(0xFF64748B));
    }
  }

  Future<void> _abrir(Map<String, dynamic> n) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (n['lida'] != true) await NotificacaoService.instance.marcarLida(n['id']);
      final idTicket = n['id_ticket'];
      if (idTicket == null) return;
      final ticket = await TicketService.instance.chamadoPorId(idTicket);
      if (ticket == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Este chamado já não está disponível para si.')));
        return;
      }
      navigator.pushNamed('/ticket_details', arguments: ticket);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Não foi possível abrir a notificação.')));
    }
  }

  Future<void> _marcarTodas() async {
    try {
      await NotificacaoService.instance.marcarTodasLidas();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Não foi possível atualizar as notificações.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Marcar todas como lidas',
            onPressed: _marcarTodas,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.cBorda, height: 1),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final lista = snap.data!;
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Ainda não tem notificações.', style: TextStyle(color: Color(0xFF64748B))),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: lista.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final n = lista[i];
              final lida = n['lida'] == true;
              final (icone, cor) = _icone(n['tipo'] as String?);
              return Container(
                decoration: BoxDecoration(
                  color: lida ? context.cSuperficie : context.cFundoSuave,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: lida ? context.cBorda : cor.withOpacity(0.5)),
                ),
                child: ListTile(
                  onTap: () => _abrir(n),
                  leading: CircleAvatar(
                    backgroundColor: cor.withOpacity(0.12),
                    child: Icon(icone, color: cor),
                  ),
                  title: Text(
                    '${n['titulo']}',
                    style: TextStyle(
                      color: context.cTexto,
                      fontWeight: lida ? FontWeight.w500 : FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ('${n['mensagem']}'.isNotEmpty) Text('${n['mensagem']}'),
                      const SizedBox(height: 4),
                      Text(
                        tempoDecorrido(n['created_at'] as String?),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: lida
                      ? null
                      : Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
