import 'package:supabase_flutter/supabase_flutter.dart';

/// Inventário de equipamentos de TI (tabela `assets`) e ligação aos chamados.
class InventarioService {
  InventarioService._();
  static final InventarioService instance = InventarioService._();

  SupabaseClient get _db => Supabase.instance.client;

  static const tipos = ['Computador', 'Notebook', 'Monitor', 'Impressora', 'Roteador', 'Outro'];
  static const situacoes = ['Em uso', 'Em estoque', 'Em manutenção', 'Baixado'];

  /// Técnicos veem todos; um cliente só vê os equipamentos de que é responsável.
  Future<List<Map<String, dynamic>>> listar() async {
    final linhas = await _db.from('assets').select().order('patrimonio');
    return List<Map<String, dynamic>>.from(linhas);
  }

  Future<List<Map<String, dynamic>>> doUtilizador(String idUsuario) async {
    final linhas = await _db
        .from('assets')
        .select()
        .eq('id_responsavel', idUsuario)
        .neq('situacao', 'Baixado')
        .order('patrimonio');
    return List<Map<String, dynamic>>.from(linhas);
  }

  Future<Map<String, dynamic>?> porId(dynamic id) =>
      _db.from('assets').select().eq('id', id).maybeSingle();

  /// {id_asset: {total, recentes}} (só técnicos). Serve para destacar defeitos recorrentes.
  Future<Map<String, Map<String, dynamic>>> estatisticas() async {
    final linhas = await _db.rpc('assets_estatisticas');
    return {
      for (final l in (linhas as List)) '${l['id_asset']}': Map<String, dynamic>.from(l as Map),
    };
  }

  /// Todos os chamados já abertos para este equipamento.
  Future<List<Map<String, dynamic>>> chamadosDoAsset(dynamic id) async {
    final linhas = await _db.rpc('chamados_do_asset', params: {'p_id': id});
    return List<Map<String, dynamic>>.from(linhas as List);
  }

  Future<void> salvar(Map<String, dynamic> campos, {dynamic id}) async {
    if (id == null) {
      await _db.from('assets').insert(campos);
    } else {
      await _db.from('assets').update(campos).eq('id', id);
    }
  }

  Future<void> excluir(dynamic id) async {
    await _db.from('assets').delete().eq('id', id);
  }

  /// Vincula (ou desvincula, com null) um equipamento a um chamado.
  Future<void> vincularAoChamado(dynamic idTicket, dynamic idAsset) async {
    final linhas =
        await _db.from('tickets').update({'id_asset': idAsset}).eq('id', idTicket).select('id');
    if (linhas.isEmpty) {
      throw PostgrestException(message: 'Só o técnico responsável pode vincular o equipamento.');
    }
  }
}
