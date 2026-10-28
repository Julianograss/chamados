import 'package:supabase_flutter/supabase_flutter.dart';

/// Apontamento de horas por chamado (tabela `ticket_worklogs`) e estimativa.
class HorasService {
  HorasService._();
  static final HorasService instance = HorasService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> listar(dynamic idTicket) async {
    final linhas = await _db
        .from('ticket_worklogs')
        .select()
        .eq('id_ticket', idTicket)
        .order('data_trabalho', ascending: false)
        .order('id', ascending: false);
    return List<Map<String, dynamic>>.from(linhas);
  }

  Future<void> registrar(dynamic idTicket, int minutos, String descricao, DateTime data) async {
    final d = '${data.year.toString().padLeft(4, '0')}-'
        '${data.month.toString().padLeft(2, '0')}-'
        '${data.day.toString().padLeft(2, '0')}';
    await _db.from('ticket_worklogs').insert({
      'id_ticket': idTicket,
      'minutos': minutos,
      'descricao': descricao.trim(),
      'data_trabalho': d,
    });
  }

  Future<void> excluir(dynamic id) async {
    await _db.from('ticket_worklogs').delete().eq('id', id);
  }

  /// Estimativa de esforço do chamado (em minutos); null remove a estimativa.
  Future<void> definirEstimativa(dynamic idTicket, int? minutos) async {
    final linhas =
        await _db.from('tickets').update({'minutos_estimados': minutos}).eq('id', idTicket).select('id');
    if (linhas.isEmpty) {
      throw PostgrestException(message: 'Só o técnico responsável pode definir a estimativa.');
    }
  }

  /// Relatório de esforço (administrador).
  Future<Map<String, dynamic>> relatorio(DateTime de, DateTime ate) async {
    final r = await _db.rpc('relatorio_esforco', params: {
      'p_de': de.toUtc().toIso8601String(),
      'p_ate': ate.toUtc().toIso8601String(),
    });
    return Map<String, dynamic>.from(r as Map);
  }

  /// "1 h 30 min", "45 min", "2 h".
  static String formatar(num? minutos) {
    if (minutos == null) return '—';
    final m = minutos.round();
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }
}
