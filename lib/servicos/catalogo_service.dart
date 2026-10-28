import 'package:supabase_flutter/supabase_flutter.dart';

/// Catálogo de serviços de TI (tabela `servicos`).
class CatalogoService {
  CatalogoService._();
  static final CatalogoService instance = CatalogoService._();

  SupabaseClient get _db => Supabase.instance.client;

  static const categorias = ['Hardware', 'Software', 'Rede', 'Outros'];
  static const prioridades = ['Baixa', 'Média', 'Alta'];
  static const tiposDeCampo = {'texto': 'Texto curto', 'multilinha': 'Texto longo', 'selecao': 'Lista de opções'};

  /// Serviços ativos (o administrador pode pedir também os inativos).
  Future<List<Map<String, dynamic>>> listar({bool incluirInativos = false}) async {
    var q = _db.from('servicos').select();
    if (!incluirInativos) q = q.eq('ativo', true);
    final linhas = await q.order('ordem').order('nome');
    return List<Map<String, dynamic>>.from(linhas);
  }

  Future<void> salvar(Map<String, dynamic> campos, {dynamic id}) async {
    if (id == null) {
      await _db.from('servicos').insert(campos);
    } else {
      await _db.from('servicos').update(campos).eq('id', id);
    }
  }

  Future<void> excluir(dynamic id) async {
    await _db.from('servicos').delete().eq('id', id);
  }

  /// Campos do serviço já com o tipo certo.
  static List<Map<String, dynamic>> camposDe(Map<String, dynamic> servico) {
    final c = servico['campos'];
    if (c is! List) return const [];
    return [for (final x in c) if (x is Map) Map<String, dynamic>.from(x)];
  }
}
