import 'package:supabase_flutter/supabase_flutter.dart';

/// Equipas (filas de atendimento) e atribuição de responsável.
class EquipasService {
  EquipasService._();
  static final EquipasService instance = EquipasService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> listar() async {
    final linhas = await _db.from('equipes').select().order('nome');
    return List<Map<String, dynamic>>.from(linhas);
  }

  /// {id_equipe: [id_usuario, ...]} (só técnicos/admin leem as associações).
  Future<Map<String, List<String>>> membros() async {
    final linhas = await _db.from('equipe_membros').select();
    final mapa = <String, List<String>>{};
    for (final l in linhas) {
      mapa.putIfAbsent('${l['id_equipe']}', () => []).add('${l['id_usuario']}');
    }
    return mapa;
  }

  /// Cria ou edita a equipa E substitui os membros numa única operação no banco:
  /// se algo falhar (ex.: alguém que não é técnico ativo), nada é alterado.
  Future<void> salvarEquipa({
    dynamic id,
    required String nome,
    String? descricao,
    String? categoria,
    required List<String> membros,
  }) async {
    await _db.rpc('salvar_equipe', params: {
      'p_id': id,
      'p_nome': nome,
      'p_descricao': descricao,
      'p_categoria': categoria,
      'p_usuarios': membros,
    });
  }

  Future<void> excluir(dynamic id) async {
    await _db.from('equipes').delete().eq('id', id);
  }

  /// Técnicos ativos com a carga atual; os da equipa [idEquipe] vêm primeiro.
  Future<List<Map<String, dynamic>>> tecnicosDisponiveis([dynamic idEquipe]) async {
    final linhas = await _db.rpc('tecnicos_disponiveis', params: {'p_equipe': idEquipe});
    return List<Map<String, dynamic>>.from(linhas as List);
  }

  Future<void> definirEquipaDoChamado(dynamic idTicket, dynamic idEquipe) =>
      _db.rpc('definir_equipe_ticket', params: {'p_id': idTicket, 'p_equipe': idEquipe});

  Future<void> atribuir(dynamic idTicket, String idTecnico) =>
      _db.rpc('atribuir_ticket', params: {'p_id': idTicket, 'p_tecnico': idTecnico});
}
