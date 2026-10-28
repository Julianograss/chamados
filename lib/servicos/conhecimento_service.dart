import 'package:supabase_flutter/supabase_flutter.dart';

/// Base de conhecimento (tabela `knowledge_articles`).
class ConhecimentoService {
  ConhecimentoService._();
  static final ConhecimentoService instance = ConhecimentoService._();

  SupabaseClient get _db => Supabase.instance.client;

  static const categorias = ['Geral', 'Hardware', 'Software', 'Rede', 'Outros'];

  /// Clientes só recebem os artigos publicados (o RLS garante o mesmo no banco).
  Future<List<Map<String, dynamic>>> listar() async {
    final linhas = await _db.from('knowledge_articles').select().order('titulo');
    return List<Map<String, dynamic>>.from(linhas);
  }

  Future<void> salvar(Map<String, dynamic> campos, {dynamic id}) async {
    if (id == null) {
      await _db.from('knowledge_articles').insert(campos);
    } else {
      await _db.from('knowledge_articles').update(campos).eq('id', id);
    }
  }

  Future<void> excluir(dynamic id) async {
    await _db.from('knowledge_articles').delete().eq('id', id);
  }

  Future<void> avaliar(dynamic id, bool util) =>
      _db.rpc('avaliar_artigo', params: {'p_id': id, 'p_util': util});

  /// Minúsculas e sem acentos (para a pesquisa ignorar "ç", "ã"...).
  static String normalizar(String texto) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final sb = StringBuffer();
    for (final c in texto.toLowerCase().split('')) {
      final i = de.indexOf(c);
      sb.write(i >= 0 ? para[i] : c);
    }
    return sb.toString();
  }

  /// Pesquisa local: todas as palavras têm de aparecer no título, resumo, tags ou conteúdo.
  static List<Map<String, dynamic>> pesquisar(List<Map<String, dynamic>> artigos, String busca) {
    final palavras = normalizar(busca).split(RegExp(r'\s+')).where((p) => p.length > 1).toList();
    if (palavras.isEmpty) return artigos;
    return artigos.where((a) {
      final texto = normalizar('${a['titulo']} ${a['resumo'] ?? ''} ${(a['tags'] as List?)?.join(' ') ?? ''} ${a['conteudo']}');
      return palavras.every(texto.contains);
    }).toList();
  }

  /// Sugestões enquanto o cliente abre um chamado: artigos do serviço escolhido
  /// e/ou que combinam com o que foi escrito. No máximo [limite].
  static List<Map<String, dynamic>> sugerir(
    List<Map<String, dynamic>> artigos, {
    dynamic idServico,
    String texto = '',
    int limite = 3,
  }) {
    final palavras = normalizar(texto)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((p) => p.length > 3)
        .toSet();
    final pontuados = <(int, Map<String, dynamic>)>[];
    for (final a in artigos) {
      if (a['publicado'] == false) continue;
      var pontos = 0;
      if (idServico != null && '${a['id_servico']}' == '$idServico') pontos += 5;
      final alvo = normalizar('${a['titulo']} ${(a['tags'] as List?)?.join(' ') ?? ''} ${a['resumo'] ?? ''}');
      for (final p in palavras) {
        if (alvo.contains(p)) pontos += 2;
      }
      if (pontos > 0) pontuados.add((pontos, a));
    }
    pontuados.sort((x, y) => y.$1.compareTo(x.$1));
    return [for (final p in pontuados.take(limite)) p.$2];
  }
}
