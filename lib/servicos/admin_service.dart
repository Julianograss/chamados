import 'package:supabase_flutter/supabase_flutter.dart';

/// Operações reservadas ao administrador: utilizadores, configuração do SLA
/// e relatório gerencial. Todas são validadas de novo no banco (RLS/funções).
class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();

  SupabaseClient get _db => Supabase.instance.client;

  // ------------------------------------------------------------------
  // Utilizadores
  // ------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listarUsuarios() async {
    final linhas = await _db
        .from('users')
        .select('id, nome, email, role, ativo, created_at')
        .order('nome');
    return List<Map<String, dynamic>>.from(linhas);
  }

  Future<List<Map<String, dynamic>>> listarConvites() async {
    final linhas = await _db.from('convites_funcao').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(linhas);
  }

  Future<void> alterarFuncao(String id, String role) =>
      _db.rpc('admin_alterar_funcao', params: {'p_id': id, 'p_role': role});

  Future<void> definirAtivo(String id, bool ativo) =>
      _db.rpc('admin_definir_ativo', params: {'p_id': id, 'p_ativo': ativo});

  /// Devolve "promovido" (a pessoa já tinha conta confirmada) ou "convite" (fica pendente).
  Future<String> convidar(String email, String role) async {
    final r = await _db.rpc('admin_convidar', params: {'p_email': email, 'p_role': role});
    return '$r';
  }

  Future<void> cancelarConvite(String email) =>
      _db.rpc('admin_cancelar_convite', params: {'p_email': email});

  // ------------------------------------------------------------------
  // Configuração do SLA
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> lerConfigSla() async {
    final r = await _db.from('sla_config').select().eq('id', 1).single();
    return Map<String, dynamic>.from(r);
  }

  Future<void> guardarConfigSla(Map<String, dynamic> campos) async {
    await _db.from('sla_config').update(campos).eq('id', 1);
  }

  Future<List<Map<String, dynamic>>> listarFeriados() async {
    final linhas = await _db.from('feriados').select().order('data');
    return List<Map<String, dynamic>>.from(linhas);
  }

  Future<void> adicionarFeriado(DateTime data, String descricao) async {
    final d = '${data.year.toString().padLeft(4, '0')}-'
        '${data.month.toString().padLeft(2, '0')}-'
        '${data.day.toString().padLeft(2, '0')}';
    await _db.from('feriados').upsert({'data': d, 'descricao': descricao.trim()});
  }

  Future<void> removerFeriado(String data) async {
    await _db.from('feriados').delete().eq('data', data);
  }

  // ------------------------------------------------------------------
  // Relatório gerencial
  // ------------------------------------------------------------------

  /// [agrupar]: "dia", "semana" ou "mes".
  Future<Map<String, dynamic>> relatorio(DateTime de, DateTime ate, String agrupar) async {
    final r = await _db.rpc('relatorio_gerencial', params: {
      'p_de': de.toUtc().toIso8601String(),
      'p_ate': ate.toUtc().toIso8601String(),
      'p_agrupar': agrupar,
    });
    return Map<String, dynamic>.from(r as Map);
  }

  /// Chamados do período (para a exportação detalhada em CSV).
  Future<List<Map<String, dynamic>>> chamadosDoPeriodo(DateTime de, DateTime ate) async {
    final linhas = await _db
        .from('tickets')
        .select()
        .gte('created_at', de.toUtc().toIso8601String())
        .lt('created_at', ate.toUtc().toIso8601String())
        .order('created_at');
    return List<Map<String, dynamic>>.from(linhas);
  }
}
