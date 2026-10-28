import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bucketAnexos = 'anexos_tickets';

class TicketService {
  TicketService._();
  static final TicketService instance = TicketService._();

  SupabaseClient get _db => Supabase.instance.client;

  String get _uid {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthException('Sessão expirada. Inicie sessão novamente.');
    }
    return uid;
  }

  // ------------------------------------------------------------------
  // Observação em "tempo real"
  // ------------------------------------------------------------------

  /// Devolve uma lista que se atualiza sozinha. Recarrega via REST (que
  /// respeita sempre o RLS):
  ///  - quando o Realtime avisa de uma alteração na tabela;
  ///  - e a cada [intervalo], como rede de segurança.
  ///
  /// O polling é necessário porque o Realtime não avisa quando um chamado
  /// "sai da visão" do utilizador (por exemplo, outro técnico o assumiu),
  /// nem se o Realtime falhar por algum motivo.
  Stream<List<Map<String, dynamic>>> _observar({
    required String tabela,
    required Future<List<Map<String, dynamic>>> Function() buscar,
    PostgresChangeFilter? filtro,
    Duration intervalo = const Duration(seconds: 5),
  }) {
    late final StreamController<List<Map<String, dynamic>>> ctrl;
    RealtimeChannel? canal;
    Timer? timer;
    var ativo = true;
    var emCurso = false;
    var jaEmitiu = false;

    Future<void> recarregar() async {
      if (!ativo || emCurso) return;
      emCurso = true;
      try {
        final dados = await buscar();
        if (ativo && !ctrl.isClosed) {
          jaEmitiu = true;
          ctrl.add(dados);
        }
      } catch (e) {
        // Falhas passageiras depois de já haver dados não devem apagar a lista.
        if (ativo && !ctrl.isClosed && !jaEmitiu) ctrl.addError(e);
      } finally {
        emCurso = false;
      }
    }

    ctrl = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        recarregar();
        try {
          canal = _db
              .channel('obs-$tabela-${DateTime.now().microsecondsSinceEpoch}')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: tabela,
                filter: filtro,
                callback: (_) => recarregar(),
              )
              .subscribe();
        } catch (_) {
          // Sem Realtime, o polling continua a atualizar a lista.
        }
        timer = Timer.periodic(intervalo, (_) => recarregar());
      },
      onCancel: () async {
        ativo = false;
        timer?.cancel();
        final c = canal;
        if (c != null) {
          try {
            await _db.removeChannel(c);
          } catch (_) {}
        }
        await ctrl.close();
      },
    );
    return ctrl.stream;
  }

  // ------------------------------------------------------------------
  // Criar / listar
  // ------------------------------------------------------------------

  /// Cria um chamado. Nasce sempre "Aberto" (por assumir), sem técnico, sem
  /// categoria e sem prioridade; a data/hora é a do servidor (`now()`).
  ///
  /// - Cliente: o chamado fica atribuído ao próprio utilizador logado.
  /// - Técnico/admin: deve passar [idCliente], o utilizador a quem o chamado
  ///   fica atribuído.
  Future<void> criar({
    required String titulo,
    required String descricao,
    String? idCliente,
    String? anexoPath,
    int? idServico,
    List<Map<String, String>> camposServico = const [],
    int? idAsset,
  }) async {
    await _db.from('tickets').insert({
      if (idServico != null) 'id_servico': idServico,
      if (idServico != null) 'campos_servico': camposServico,
      if (idAsset != null) 'id_asset': idAsset,
      if (anexoPath != null) 'anexo_path': anexoPath,
      'id_cliente': idCliente ?? _uid,
      'titulo': titulo.trim(),
      'descricao': descricao.trim(),
      'status': 'Aberto',
    });
  }

  /// Utilizadores com role "cliente" (para o técnico escolher ao criar um chamado).
  Future<List<Map<String, dynamic>>> listarClientes() async {
    final linhas = await _db
        .from('users')
        .select('id, nome, email')
        .eq('role', 'cliente')
        .order('nome');
    return List<Map<String, dynamic>>.from(linhas);
  }

  /// Chamados visíveis para o utilizador, do mais recente para o mais antigo.
  ///  - [todos] = false (cliente): apenas os seus
  ///  - [todos] = true (técnico/admin): o RLS devolve os chamados por assumir
  ///    (visíveis a todos os técnicos) e os que o próprio assumiu; o admin vê todos.
  Stream<List<Map<String, dynamic>>> chamados({required bool todos}) {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const Stream.empty();
    return _observar(
      tabela: 'tickets',
      filtro: todos
          ? null
          : PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id_cliente',
              value: uid,
            ),
      buscar: () async {
        final base = _db.from('tickets').select();
        final filtrado = todos ? base : base.eq('id_cliente', uid);
        final linhas = await filtrado.order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(linhas);
      },
    );
  }

  /// Um único chamado (para a tela de detalhes). Lista vazia = o chamado já
  /// não está visível para este utilizador.
  Stream<List<Map<String, dynamic>>> ticket(dynamic id) {
    return _observar(
      tabela: 'tickets',
      filtro: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: id,
      ),
      buscar: () async {
        final linhas = await _db.from('tickets').select().eq('id', id);
        return List<Map<String, dynamic>>.from(linhas);
      },
    );
  }

  // ------------------------------------------------------------------
  // Ações da equipa técnica
  // ------------------------------------------------------------------

  /// Assume o chamado (passa a "Em Andamento" e deixa de aparecer aos outros
  /// técnicos). Devolve false se outro técnico o assumiu primeiro.
  Future<bool> assumir(dynamic id) async {
    final r = await _db.rpc('assumir_ticket', params: {'p_id': id});
    return r == true;
  }

  /// Passa o chamado para outro técnico (deixa de aparecer a quem transfere).
  Future<void> transferir(dynamic id, String idTecnico) async {
    await _db.rpc('transferir_ticket', params: {
      'p_id': id,
      'p_novo_tecnico': idTecnico,
    });
  }

  Future<void> _atualizar(dynamic id, Map<String, dynamic> campos) async {
    final linhas = await _db.from('tickets').update(campos).eq('id', id).select();
    if (linhas.isEmpty) {
      throw PostgrestException(
        message: 'Só o técnico responsável pode alterar este chamado.',
      );
    }
  }

  Future<void> alterarStatus(dynamic id, String status) =>
      _atualizar(id, {'status': status});

  /// O técnico responsável define a categoria (Hardware, Software...) e/ou a prioridade.
  Future<void> classificar(dynamic id, {String? categoria, String? prioridade}) {
    final campos = <String, dynamic>{
      if (categoria != null) 'categoria': categoria,
      if (prioridade != null) 'prioridade': prioridade,
    };
    if (campos.isEmpty) return Future.value();
    return _atualizar(id, campos);
  }

  /// Técnicos e administradores (candidatos a receber uma transferência).
  Future<List<Map<String, dynamic>>> listarTecnicos() async {
    final linhas = await _db
        .from('users')
        .select('id, nome, role')
        .inFilter('role', ['tecnico', 'admin'])
        .order('nome');
    return List<Map<String, dynamic>>.from(linhas);
  }

  /// Mapa id -> nome para os utilizadores pedidos (os que o RLS permitir ler).
  Future<Map<String, String>> nomesDe(List<String> ids) async {
    if (ids.isEmpty) return {};
    final linhas = await _db.from('users').select('id, nome').inFilter('id', ids);
    return {for (final l in linhas) '${l['id']}': '${l['nome']}'};
  }

  // ------------------------------------------------------------------
  // Comentários
  // ------------------------------------------------------------------

  Stream<List<Map<String, dynamic>>> comentarios(dynamic idTicket) {
    return _observar(
      tabela: 'comments',
      filtro: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id_ticket',
        value: idTicket,
      ),
      buscar: () async {
        final linhas = await _db
            .from('comments')
            .select()
            .eq('id_ticket', idTicket)
            .order('created_at', ascending: true)
            .order('id', ascending: true);
        return List<Map<String, dynamic>>.from(linhas);
      },
    );
  }

  /// Envia um comentário. Pode ter texto, imagem ([anexoPath]) ou os dois.
  /// [interno] = nota interna (só a equipa técnica a vê).
  Future<void> comentar(
    dynamic idTicket,
    String mensagem, {
    String? anexoPath,
    bool interno = false,
  }) async {
    await _db.from('comments').insert({
      'id_ticket': idTicket,
      'id_autor': _uid,
      'tipo': interno ? 'nota_interna' : 'mensagem',
      'mensagem': mensagem.trim(),
      if (anexoPath != null) 'anexo_path': anexoPath,
    });
  }

  // ------------------------------------------------------------------
  // Cancelar / reabrir (funções no banco que validam quem pode fazê-lo)
  // ------------------------------------------------------------------

  Future<void> cancelar(dynamic id) => _db.rpc('cancelar_ticket', params: {'p_id': id});

  Future<void> reabrir(dynamic id) => _db.rpc('reabrir_ticket', params: {'p_id': id});

  /// O cliente avalia o atendimento (1 a 5 estrelas) no pedido de CSAT do chat.
  Future<void> avaliar(dynamic idComentario, int nota) =>
      _db.rpc('avaliar_atendimento', params: {'p_id_comentario': idComentario, 'p_nota': nota});

  // ------------------------------------------------------------------
  // Anexos (imagens no Storage, bucket privado "anexos_tickets")
  // ------------------------------------------------------------------

  static const int tamanhoMaximoImagem = 5 * 1024 * 1024;

  /// Envia a imagem para `<uid>/<timestamp>.<ext>` e devolve o caminho, que é
  /// guardado em `comments.anexo_path`.
  Future<String> enviarImagem(XFile imagem) async {
    final nome = imagem.name.toLowerCase();
    final ext = nome.endsWith('.png') ? 'png' : (nome.endsWith('.webp') ? 'webp' : 'jpg');
    final tipo = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
    final bytes = await imagem.readAsBytes();
    if (bytes.length > tamanhoMaximoImagem) {
      throw const FormatException('A imagem é demasiado grande (máximo 5 MB).');
    }
    final caminho = '$_uid/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _db.storage
        .from(_bucketAnexos)
        .uploadBinary(caminho, bytes, fileOptions: FileOptions(contentType: tipo));
    return caminho;
  }

  /// Apaga um ficheiro enviado (se o comentário falhar depois do upload).
  Future<void> removerImagem(String caminho) async {
    try {
      await _db.storage.from(_bucketAnexos).remove([caminho]);
    } catch (_) {}
  }

  /// Link temporário (1 hora) para mostrar uma imagem do bucket privado.
  Future<String> urlDoAnexo(String caminho) =>
      _db.storage.from(_bucketAnexos).createSignedUrl(caminho, 3600);

  // ------------------------------------------------------------------
  // Pendências, histórico e acesso direto a um chamado
  // ------------------------------------------------------------------

  /// Coloca o chamado em "Aguardando Usuário" ou "Aguardando Fornecedor".
  /// O motivo é obrigatório e o SLA fica em pausa até o atendimento ser retomado.
  Future<void> definirPendente(dynamic id, String status, String motivo) =>
      _atualizar(id, {'status': status, 'motivo_pendencia': motivo.trim()});

  /// Retoma o atendimento ("Em Andamento") e retoma o SLA.
  Future<void> retomar(dynamic id) => _atualizar(id, {'status': 'Em Andamento'});

  /// Todos os eventos do chamado (só a equipa técnica tem acesso).
  Future<List<Map<String, dynamic>>> historico(dynamic id) async {
    final linhas = await _db
        .from('ticket_history')
        .select()
        .eq('id_ticket', id)
        .order('created_at', ascending: true)
        .order('id', ascending: true);
    return List<Map<String, dynamic>>.from(linhas);
  }

  /// Um chamado pelo id (ex.: ao tocar numa notificação). Null se não o puder ver.
  Future<Map<String, dynamic>?> chamadoPorId(dynamic id) =>
      _db.from('tickets').select().eq('id', id).maybeSingle();
}
