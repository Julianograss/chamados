import 'package:flutter/material.dart';

/// "#TK-12"
String codigoTicket(dynamic id) => '#TK-$id';

/// "Há 15 min", "Há 2 horas", "Há 3 dias" ou "12/10/2026".
String tempoDecorrido(String? iso) {
  final data = DateTime.tryParse(iso ?? '')?.toLocal();
  if (data == null) return '';
  final d = DateTime.now().difference(data);
  if (d.inMinutes < 1) return 'Agora mesmo';
  if (d.inMinutes < 60) return 'Há ${d.inMinutes} min';
  if (d.inHours < 24) return 'Há ${d.inHours} ${d.inHours == 1 ? 'hora' : 'horas'}';
  if (d.inDays < 7) return 'Há ${d.inDays} ${d.inDays == 1 ? 'dia' : 'dias'}';
  return '${data.day.toString().padLeft(2, '0')}/'
      '${data.month.toString().padLeft(2, '0')}/${data.year}';
}

/// "12/10, 09:45"
String dataHora(String? iso) {
  final data = DateTime.tryParse(iso ?? '')?.toLocal();
  if (data == null) return '';
  return '${data.day.toString().padLeft(2, '0')}/'
      '${data.month.toString().padLeft(2, '0')}, '
      '${data.hour.toString().padLeft(2, '0')}:'
      '${data.minute.toString().padLeft(2, '0')}';
}

class CoresPrioridade {
  final Color texto;
  final Color fundo;
  const CoresPrioridade(this.texto, this.fundo);
}

CoresPrioridade coresDaPrioridade(String? p) {
  switch (p) {
    case 'Alta':
      return const CoresPrioridade(Color(0xFFE11D48), Color(0xFFFFE4E6));
    case 'Média':
      return const CoresPrioridade(Color(0xFFD97706), Color(0xFFFEF3C7));
    case 'Baixa':
      return const CoresPrioridade(Color(0xFF059669), Color(0xFFD1FAE5));
    default: // ainda sem prioridade (o técnico ainda não classificou)
      return const CoresPrioridade(Color(0xFF64748B), Color(0xFFF1F5F9));
  }
}

Color corDoStatus(String? s) {
  switch (s) {
    case 'Em Andamento':
      return const Color(0xFFD97706);
    case 'Resolvido':
      return const Color(0xFF059669);
    case 'Aguardando Usuário':
    case 'Aguardando Fornecedor':
      return const Color(0xFF7C3AED);
    case 'Cancelado':
      return const Color(0xFF64748B);
    default:
      return const Color(0xFF2563EB);
  }
}

// ---------------------------------------------------------------------
// SLA (Acordo de Nível de Serviço)
// Os prazos são calculados no banco (prioridade, horário comercial, feriados,
// pausas) e guardados em `prazo_resolucao` / `prazo_primeira_resposta`.
// ---------------------------------------------------------------------

enum NivelSla { ok, atencao, critico, vencido, pausado, noPrazo, foraDoPrazo }

class Sla {
  final NivelSla nivel;
  final String texto;
  final Color cor;
  final Color fundo;
  final IconData icone;

  /// Pede atenção imediata (vermelho / ícone de fogo).
  bool get urgente => nivel == NivelSla.critico || nivel == NivelSla.vencido;

  const Sla(this.nivel, this.texto, this.cor, this.fundo, this.icone);
}

String _duracaoCurta(Duration d) {
  final dias = d.inDays;
  final horas = d.inHours % 24;
  final min = d.inMinutes % 60;
  if (dias > 0) return '$dias d $horas h';
  if (d.inHours > 0) return '${d.inHours} h $min min';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} min';
}

const _verde = Color(0xFF059669);
const _verdeFundo = Color(0xFFD1FAE5);
const _vermelho = Color(0xFFE11D48);
const _vermelhoFundo = Color(0xFFFFE4E6);
const _ambar = Color(0xFFD97706);
const _ambarFundo = Color(0xFFFEF3C7);

bool _estaPendente(String status) =>
    status == 'Aguardando Usuário' || status == 'Aguardando Fornecedor';

/// Estado do SLA de RESOLUÇÃO, ou null se não se aplica (sem prioridade
/// definida, sem prazo calculado ou cancelado).
///  - ativo: contagem decrescente (verde -> âmbar -> vermelho com fogo)
///  - pendente ("Aguardando ..."): SLA pausado
///  - resolvido: "dentro/fora do SLA"
Sla? calcularSla(Map<String, dynamic> t, {DateTime? agora}) {
  final status = '${t['status']}';
  final criado = DateTime.tryParse('${t['created_at']}');
  final prazo = DateTime.tryParse('${t['prazo_resolucao']}');
  if (prazo == null || criado == null || status == 'Cancelado') return null;

  if (status == 'Resolvido') {
    final fim = DateTime.tryParse('${t['data_fechamento']}');
    if (fim == null) return null;
    return fim.isAfter(prazo)
        ? const Sla(NivelSla.foraDoPrazo, 'Resolvido fora do SLA', _vermelho, _vermelhoFundo,
            Icons.error_outline)
        : const Sla(NivelSla.noPrazo, 'Resolvido dentro do SLA', _verde, _verdeFundo,
            Icons.check_circle_outline);
  }

  if (_estaPendente(status) || t['sla_pausado_em'] != null) {
    return const Sla(NivelSla.pausado, 'SLA pausado', Color(0xFF7C3AED), Color(0xFFEDE9FE),
        Icons.pause_circle_outline);
  }

  final restante = prazo.difference(agora ?? DateTime.now());
  if (restante.inSeconds <= 0) {
    return Sla(NivelSla.vencido, 'SLA vencido há ${_duracaoCurta(-restante)}', _vermelho,
        _vermelhoFundo, Icons.local_fire_department);
  }
  final texto = 'Restam ${_duracaoCurta(restante)}';
  final agoraT = agora ?? DateTime.now();

  // Os instantes de atenção (50 %) e alerta (75 % do SLA consumido) são calculados
  // no banco, no mesmo calendário do prazo (horário comercial, feriados, pausas).
  final atencao = DateTime.tryParse('${t['prazo_atencao']}');
  final alerta = DateTime.tryParse('${t['prazo_alerta']}');
  if (alerta != null && atencao != null) {
    if (!agoraT.isBefore(alerta)) {
      return Sla(NivelSla.critico, texto, _vermelho, _vermelhoFundo, Icons.local_fire_department);
    }
    if (!agoraT.isBefore(atencao)) {
      return Sla(NivelSla.atencao, texto, _ambar, _ambarFundo, Icons.timer_outlined);
    }
    return Sla(NivelSla.ok, texto, _verde, _verdeFundo, Icons.schedule);
  }

  // Chamados sem esses instantes: estimativa pelo tempo corrido.
  var total = prazo.difference(criado);
  if (total.inSeconds <= 0) total = const Duration(hours: 1);
  final fracao = restante.inSeconds / total.inSeconds;
  if (fracao < 0.25) {
    return Sla(NivelSla.critico, texto, _vermelho, _vermelhoFundo, Icons.local_fire_department);
  }
  if (fracao < 0.5) {
    return Sla(NivelSla.atencao, texto, _ambar, _ambarFundo, Icons.timer_outlined);
  }
  return Sla(NivelSla.ok, texto, _verde, _verdeFundo, Icons.schedule);
}

/// Estado do prazo de PRIMEIRA RESPOSTA, ou null se não se aplica.
/// Respondido: mostra se foi dentro do prazo. Por responder: contagem.
Sla? calcularSlaPrimeiraResposta(Map<String, dynamic> t, {DateTime? agora}) {
  final status = '${t['status']}';
  final prazo = DateTime.tryParse('${t['prazo_primeira_resposta']}');
  if (prazo == null || status == 'Cancelado') return null;

  final resposta = DateTime.tryParse('${t['primeira_resposta_em']}');
  if (resposta != null) {
    final criado = DateTime.tryParse('${t['created_at']}');
    final quando = criado == null ? '' : ' (${_duracaoCurta(resposta.difference(criado))})';
    return resposta.isAfter(prazo)
        ? Sla(NivelSla.foraDoPrazo, '1ª resposta fora do prazo$quando', _vermelho, _vermelhoFundo,
            Icons.mark_chat_unread_outlined)
        : Sla(NivelSla.noPrazo, '1ª resposta no prazo$quando', _verde, _verdeFundo,
            Icons.mark_chat_read_outlined);
  }
  if (status == 'Resolvido') return null;

  final restante = prazo.difference(agora ?? DateTime.now());
  if (restante.inSeconds <= 0) {
    return Sla(NivelSla.vencido, '1ª resposta atrasada há ${_duracaoCurta(-restante)}', _vermelho,
        _vermelhoFundo, Icons.local_fire_department);
  }
  return Sla(NivelSla.ok, '1ª resposta em ${_duracaoCurta(restante)}', _ambar, _ambarFundo,
      Icons.mark_chat_unread_outlined);
}
