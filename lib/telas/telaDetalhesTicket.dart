import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/auth_service.dart';
import '../servicos/configuracoes.dart';
import '../servicos/equipas_service.dart';
import '../servicos/formatadores.dart';
import '../servicos/ticket_service.dart';
import '../tema.dart';
import 'cartoesChamado.dart';
import 'imagemAnexo.dart';

/// Mensagem de aviso para mostrar ao utilizador (não é um erro técnico).
class _Aviso implements Exception {
  final String texto;
  const _Aviso(this.texto);
}

class telaDetalhesTicket extends StatefulWidget {
  const telaDetalhesTicket({super.key});

  @override
  State<telaDetalhesTicket> createState() => _telaDetalhesTicketState();
}

class _telaDetalhesTicketState extends State<telaDetalhesTicket> {
  final _comentarioCtrl = TextEditingController();
  final _scroll = ScrollController();

  // Imagem escolhida na galeria, à espera de ser enviada
  Uint8List? _imagemBytes;
  XFile? _imagem;

  // Para avisar de mensagens novas e rolar a conversa
  List<Map<String, dynamic>>? _ultimosComentarios;

  bool _iniciado = false;
  Map<String, dynamic>? _inicial;
  Stream<List<Map<String, dynamic>>>? _ticketStream;
  Stream<List<Map<String, dynamic>>>? _comentariosStream;

  bool _staff = false;
  bool _admin = false;
  bool _acaoEmCurso = false;
  bool _enviando = false;
  bool _notaInterna = false; // só técnicos: a mensagem é uma nota interna
  Timer? _relogio;
  Map<String, String> _equipas = {}; // id da equipa -> nome

  Map<String, String> _nomes = {};
  String _chaveNomes = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    _carregarEquipas();
    // Atualiza a contagem do SLA a cada 30 s.
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    // O chamado é enviado pela Dashboard via Navigator (arguments).
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _inicial = Map<String, dynamic>.from(args);
      final id = _inicial!['id'];
      _ticketStream = TicketService.instance.ticket(id);
      _comentariosStream = TicketService.instance.comentarios(id);
    }
    _carregarPapel();
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _comentarioCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- dados

  Future<void> _carregarPapel() async {
    try {
      final perfil = await AuthService.instance.perfilAtual();
      final role = perfil?['role'];
      if (mounted) {
        setState(() {
          _staff = role == 'tecnico' || role == 'admin';
          _admin = role == 'admin';
        });
      }
    } catch (_) {
      // Mantém o comportamento de cliente.
    }
  }

  Future<void> _carregarNomes(Map<String, dynamic> t) async {
    final ids = <String>{
      if (t['id_cliente'] != null) '${t['id_cliente']}',
      if (t['id_tecnico'] != null) '${t['id_tecnico']}',
    };
    final chave = (ids.toList()..sort()).join(',');
    if (chave == _chaveNomes) return;
    _chaveNomes = chave;
    if (ids.isEmpty) return;
    try {
      final nomes = await TicketService.instance.nomesDe(ids.toList());
      if (mounted) setState(() => _nomes = nomes);
    } catch (_) {
      // Nomes são apenas informativos.
    }
  }

  // --------------------------------------------------------------- ações

  void _mensagem(String texto, {bool erro = true}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? const Color(0xFFE11D48) : const Color(0xFF059669),
        ),
      );
  }

  /// Executa uma ação da equipa técnica. Devolve true se correu bem.
  Future<bool> _executar(Future<void> Function() acao, String sucesso) async {
    setState(() => _acaoEmCurso = true);
    try {
      await acao();
      if (mounted) _mensagem(sucesso, erro: false);
      return true;
    } on _Aviso catch (e) {
      if (mounted) _mensagem(e.texto);
    } on PostgrestException catch (e) {
      if (mounted) _mensagem(e.message);
    } catch (_) {
      if (mounted) {
        _mensagem('Não foi possível concluir a ação. Verifique a ligação e tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _acaoEmCurso = false);
    }
    return false;
  }

  Future<void> _acaoPrincipal(Map<String, dynamic> t) async {
    final id = t['id'];
    if (t['id_tecnico'] == null) {
      await _executar(
        () async {
          final ok = await TicketService.instance.assumir(id);
          if (!ok) {
            throw const _Aviso('Este chamado já foi assumido por outro técnico.');
          }
        },
        'Chamado assumido por si. Já pode definir a categoria e a prioridade.',
      );
    } else if ('${t['status']}' == 'Resolvido') {
      await _executar(
        () => TicketService.instance.reabrir(id),
        'Chamado reaberto.',
      );
    } else {
      // Só se pode resolver depois de explicar como o problema foi solucionado
      // (o banco também valida isto).
      if (!_temExplicacaoDaEquipa) {
        _mensagem(
          'Antes de resolver, escreva um comentário ou uma nota interna '
          'a explicar como o problema foi solucionado.',
        );
        return;
      }
      await _executar(
        () => TicketService.instance.alterarStatus(id, 'Resolvido'),
        'Chamado resolvido.',
      );
    }
  }

  Future<void> _transferir(Map<String, dynamic> t) async {
    List<Map<String, dynamic>> tecnicos;
    try {
      tecnicos = await TicketService.instance.listarTecnicos();
    } catch (_) {
      if (mounted) _mensagem('Não foi possível carregar a lista de técnicos.');
      return;
    }
    if (!mounted) return;

    final meuId = AuthService.instance.utilizadorAtual?.id;
    final opcoes =
        tecnicos.where((u) => '${u['id']}' != '${t['id_tecnico']}').toList();
    if (opcoes.isEmpty) {
      _mensagem('Não há outros técnicos disponíveis.');
      return;
    }

    final escolhido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: context.cSuperficie,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Transferir para',
                style: TextStyle(
                  color: context.cTexto,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in opcoes)
                    ListTile(
                      leading: const Icon(Icons.person_outline, color: Color(0xFF042C5C)),
                      title: Text('${u['nome']}${'${u['id']}' == meuId ? ' (eu)' : ''}'),
                      subtitle: Text(_rotuloRole(u['role'] as String?)),
                      onTap: () => Navigator.of(ctx).pop(u),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (escolhido == null) return;

    final ok = await _executar(
      () => TicketService.instance.transferir(t['id'], '${escolhido['id']}'),
      'Chamado transferido para ${escolhido['nome']}.',
    );
    // O chamado passa a ser do outro técnico e sai da visão de quem transferiu.
    if (ok && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _carregarEquipas() async {
    try {
      final lista = await EquipasService.instance.listar();
      if (mounted) setState(() => _equipas = {for (final e in lista) '${e['id']}': '${e['nome']}'});
    } catch (_) {}
  }

  /// Encaminha o chamado para uma equipa (fila) ou tira-o de qualquer equipa.
  Future<void> _escolherEquipa(Map<String, dynamic> t) async {
    List<Map<String, dynamic>> lista;
    try {
      lista = await EquipasService.instance.listar();
    } catch (_) {
      _mensagem('Não foi possível carregar as equipas.');
      return;
    }
    if (!mounted) return;
    final escolhida = await showDialog<Object?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Encaminhar para a equipa'),
        children: [
          for (final e in lista)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(e['id']),
              child: Text('${e['nome']}${'${t['id_equipe']}' == '${e['id']}' ? '  ✓' : ''}'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('__nenhuma__'),
            child: const Text('Sem equipa'),
          ),
        ],
      ),
    );
    if (escolhida == null || !mounted) return;
    await _executar(
      () => EquipasService.instance.definirEquipaDoChamado(t['id'], escolhida == '__nenhuma__' ? null : escolhida),
      'Chamado encaminhado.',
    );
  }

  /// Atribui o chamado a um técnico, mostrando a carga de cada um (os da equipa primeiro).
  Future<void> _atribuir(Map<String, dynamic> t) async {
    List<Map<String, dynamic>> lista;
    try {
      lista = await EquipasService.instance.tecnicosDisponiveis(t['id_equipe']);
    } catch (_) {
      _mensagem('Não foi possível carregar os técnicos.');
      return;
    }
    if (!mounted) return;
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.cSuperficie,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Atribuir a um técnico',
                style: TextStyle(color: context.cTexto, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            for (final u in lista)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text('${u['nome']}'),
                subtitle: Text(
                  '${u['em_andamento']} em curso${u['na_equipa'] == true ? ' · da equipa' : ''}',
                ),
                onTap: () => Navigator.of(ctx).pop('${u['id']}'),
              ),
          ],
        ),
      ),
    );
    if (escolhido == null || !mounted) return;
    await _executar(() => EquipasService.instance.atribuir(t['id'], escolhido), 'Chamado atribuído.');
  }

  /// Há pelo menos um comentário ou nota interna de um técnico/admin?
  bool get _temExplicacaoDaEquipa => (_ultimosComentarios ?? const []).any((c) {
        final tipo = c['tipo'];
        final role = c['autor_role'];
        return (tipo == 'mensagem' || tipo == 'nota_interna' || tipo == null) &&
            (role == 'tecnico' || role == 'admin');
      });

  /// Respostas rápidas (macros) para a equipa técnica.
  static const _macros = <(String, String)>[
    ('Reiniciar o computador',
        'Por favor, reinicie o computador e confirme se o problema persiste.'),
    ('Pedir captura de ecrã',
        'Pode enviar uma captura de ecrã do erro apresentado? Isso ajuda-nos a perceber melhor o problema.'),
    ('Verificar a ligação à rede',
        'Por favor, verifique se está ligado à rede/Wi-Fi e se consegue abrir outros sites. Diga-nos o resultado.'),
    ('Pedir mais detalhes',
        'Pode dar-nos mais detalhes? Quando o problema começou e o que estava a fazer na altura?'),
    ('Atualizar o software',
        'Por favor, atualize o software para a versão mais recente e volte a testar.'),
    ('Estamos a analisar',
        'Recebemos o seu chamado e já estamos a analisá-lo. Voltamos com novidades em breve.'),
    ('Confirmar a resolução',
        'O problema deverá estar resolvido. Pode confirmar se está tudo a funcionar como esperado?'),
  ];

  Future<void> _abrirMacros() async {
    final texto = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.cSuperficie,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Respostas rápidas',
                  style: TextStyle(
                    color: context.cTexto,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in _macros)
                      ListTile(
                        leading: const Icon(Icons.bolt, color: Color(0xFFD97706)),
                        title: Text(m.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(m.$2, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(ctx).pop(m.$2),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (texto == null || !mounted) return;
    // Insere no campo (sem enviar), para o técnico poder ajustar o texto.
    final atual = _comentarioCtrl.text;
    final novo = atual.trim().isEmpty ? texto : '${atual.trimRight()}\n$texto';
    _comentarioCtrl.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: novo.length),
    );
  }

  /// O cliente avalia o atendimento (1 a 5 estrelas).
  Future<void> _avaliar(dynamic idComentario, int nota) => _executar(
        () => TicketService.instance.avaliar(idComentario, nota),
        'Obrigado pela sua avaliação!',
      );

  /// Pede o motivo da pendência (obrigatório). Devolve null se cancelado.
  Future<String?> _pedirMotivo(String titulo) {
    return showDialog<String>(
      context: context,
      builder: (_) => _DialogoMotivo(titulo: titulo),
    );
  }

  static String _textoDoEvento(Map<String, dynamic> h) {
    final antes = h['valor_anterior'] ?? '—';
    final depois = h['valor_novo'] ?? '—';
    switch (h['evento']) {
      case 'criado':
        return 'Chamado criado';
      case 'atribuido':
        return 'Atribuído a $depois';
      case 'desatribuido':
        return 'Atribuição removida (era $antes)';
      case 'transferido':
        return 'Transferido de $antes para $depois';
      case 'status_alterado':
        return 'Estado: $antes → $depois';
      case 'pendente':
        return 'Em espera: $depois (SLA pausado)';
      case 'resolvido':
        return 'Chamado resolvido';
      case 'cancelado':
        return 'Chamado cancelado';
      case 'reaberto':
        return 'Chamado reaberto';
      case 'prioridade_alterada':
        return 'Prioridade: $antes → $depois';
      case 'categoria_alterada':
        return 'Categoria: $antes → $depois';
      case 'avaliacao':
        return 'Cliente avaliou o atendimento: $depois/5';
      case 'equipe_alterada':
        return 'Equipa: $antes → $depois';
      case 'equipamento_alterado':
        return 'Equipamento: $antes → $depois';
      case 'estimativa_alterada':
        return 'Estimativa: ${antes == '—' ? '—' : '$antes min'} → ${depois == '—' ? '—' : '$depois min'}';
      case 'horas_registradas':
        return 'Horas registadas: $depois min';
      default:
        return '${h['evento']}';
    }
  }

  static IconData _iconeDoEvento(String? evento) {
    switch (evento) {
      case 'criado':
        return Icons.add_circle_outline;
      case 'atribuido':
      case 'desatribuido':
      case 'transferido':
        return Icons.swap_horiz;
      case 'pendente':
        return Icons.pause_circle_outline;
      case 'resolvido':
        return Icons.check_circle_outline;
      case 'cancelado':
        return Icons.cancel_outlined;
      case 'reaberto':
        return Icons.refresh;
      case 'avaliacao':
        return Icons.star_outline;
      case 'equipe_alterada':
        return Icons.groups_outlined;
      case 'equipamento_alterado':
        return Icons.devices_other;
      case 'horas_registradas':
      case 'estimativa_alterada':
        return Icons.timer_outlined;
      default:
        return Icons.edit_note;
    }
  }

  /// Histórico completo de eventos do chamado (só equipa técnica).
  Future<void> _abrirHistorico(dynamic id) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cSuperficie,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Histórico do chamado',
                  style: TextStyle(color: context.cTexto, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: TicketService.instance.historico(id),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Não foi possível carregar o histórico.'),
                      );
                    }
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final lista = snap.data!;
                    if (lista.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Ainda não há eventos registados.'),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: lista.length,
                      itemBuilder: (context, i) {
                        final h = lista[i];
                        final detalhe = '${h['detalhe'] ?? ''}'.trim();
                        return ListTile(
                          leading: Icon(_iconeDoEvento(h['evento'] as String?), color: const Color(0xFF0066FF)),
                          title: Text(_textoDoEvento(h), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${h['usuario_nome']} · ${dataHora(h['created_at'] as String?)}'
                            '${detalhe.isEmpty ? '' : '\n$detalhe'}',
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Menu "⋮": ações de exceção (cancelar / reabrir) conforme o estado e quem é o utilizador.
  Future<void> _aoEscolherMenu(String opcao, Map<String, dynamic> t) async {
    final id = t['id'];
    if (opcao == 'definir_equipa') {
      await _escolherEquipa(t);
      return;
    }
    if (opcao == 'atribuir') {
      await _atribuir(t);
      return;
    }
    if (opcao == 'historico') {
      await _abrirHistorico(id);
      return;
    }
    if (opcao == 'aguardar_usuario' || opcao == 'aguardar_fornecedor') {
      final usuario = opcao == 'aguardar_usuario';
      final motivo = await _pedirMotivo(
        usuario ? 'Motivo: aguardar utilizador' : 'Motivo: aguardar fornecedor',
      );
      if (motivo == null || !mounted) return;
      await _executar(
        () => TicketService.instance.definirPendente(
          id,
          usuario ? 'Aguardando Usuário' : 'Aguardando Fornecedor',
          motivo,
        ),
        'Chamado em espera. O SLA ficou em pausa.',
      );
      return;
    }
    if (opcao == 'retomar') {
      await _executar(() => TicketService.instance.retomar(id), 'Atendimento retomado.');
      return;
    }
    if (opcao == 'cancelar') {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancelar chamado?'),
          content: const Text(
            'O chamado deixará de estar ativo. Poderá reabri-lo mais tarde, se precisar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Voltar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cancelar chamado', style: TextStyle(color: Color(0xFFE11D48))),
            ),
          ],
        ),
      );
      if (confirmou != true || !mounted) return;
      await _executar(() => TicketService.instance.cancelar(id), 'Chamado cancelado.');
    } else if (opcao == 'reabrir') {
      await _executar(() => TicketService.instance.reabrir(id), 'Chamado reaberto.');
    }
  }

  /// Abre a galeria do dispositivo para escolher uma imagem a enviar no chat.
  Future<void> _escolherImagem() async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (img == null) return;
      final bytes = await img.readAsBytes();
      if (bytes.length > TicketService.tamanhoMaximoImagem) {
        if (mounted) _mensagem('A imagem é demasiado grande (máximo 5 MB).');
        return;
      }
      if (mounted) {
        setState(() {
          _imagem = img;
          _imagemBytes = bytes;
        });
      }
    } catch (_) {
      if (mounted) _mensagem('Não foi possível abrir a galeria. Verifique as permissões.');
    }
  }

  void _removerImagem() => setState(() {
        _imagem = null;
        _imagemBytes = null;
      });

  Future<void> _enviarComentario() async {
    final texto = _comentarioCtrl.text.trim();
    final imagem = _imagem;
    if ((texto.isEmpty && imagem == null) || _inicial == null || _enviando) return;
    setState(() => _enviando = true);
    String? caminho;
    try {
      if (imagem != null) caminho = await TicketService.instance.enviarImagem(imagem);
      await TicketService.instance.comentar(
        _inicial!['id'],
        texto,
        anexoPath: caminho,
        interno: _staff && _notaInterna,
      );
      _comentarioCtrl.clear();
      _removerImagem();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (_) {
      if (caminho != null) await TicketService.instance.removerImagem(caminho);
      if (mounted) {
        _mensagem(_staff
            ? 'Não foi possível enviar. Para comentar, assuma primeiro o chamado.'
            : 'Não foi possível enviar a mensagem.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Avisa de mensagens novas (se ativado nas Configurações) e rola a conversa.
  void _aoReceberComentarios(List<Map<String, dynamic>> lista) {
    final antes = _ultimosComentarios;
    _ultimosComentarios = lista;
    if (antes == null || lista.length <= antes.length) return;

    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    final ultimo = lista.last;
    final meuId = AuthService.instance.utilizadorAtual?.id;
    if ('${ultimo['id_autor']}' != meuId && Configuracoes.instance.notificacoes.value) {
      _mensagem('Nova mensagem de ${ultimo['autor_nome'] ?? 'Utilizador'}.', erro: false);
    }
  }

  static String _rotuloRole(String? role) {
    switch (role) {
      case 'tecnico':
        return 'Técnico';
      case 'admin':
        return 'Administrador';
      default:
        return 'Cliente';
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (_ticketStream == null || _inicial == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chamado')),
        body: const Center(child: Text('Chamado não encontrado.')),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ticketStream,
      builder: (context, snapshot) {
        final lista = snapshot.data;
        if (lista != null && lista.isEmpty) {
          // O chamado deixou de ser visível (por exemplo, outro técnico assumiu-o).
          return Scaffold(
            appBar: AppBar(title: const Text('Chamado')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Este chamado já não está disponível para si.\n'
                  'Provavelmente foi assumido por outro técnico.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), height: 1.4),
                ),
              ),
            ),
          );
        }
        final ticket = (lista != null && lista.isNotEmpty) ? lista.first : _inicial!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _carregarNomes(ticket);
        });
        return _buildTela(ticket);
      },
    );
  }

  Widget _buildTela(Map<String, dynamic> ticket) {
    final titulo = '${ticket['titulo'] ?? ''}';
    final descricao = '${ticket['descricao'] ?? ''}';
    final categoria = (ticket['categoria'] as String?) ?? 'Por definir';
    final status = '${ticket['status'] ?? ''}';
    final prioridade = ticket['prioridade'] as String?;
    final coresPrioridade = coresDaPrioridade(prioridade);

    // Sem técnico = "por assumir" (visível a todos os técnicos). Depois de
    // assumido, só o responsável (ou admin) classifica, resolve e transfere.
    final meuId = AuthService.instance.utilizadorAtual?.id;
    final semTecnico = ticket['id_tecnico'] == null;
    final podeGerir = !semTecnico && (_admin || '${ticket['id_tecnico']}' == meuId);

    final ehDono = '${ticket['id_cliente']}' == meuId;
    final encerrado = status == 'Resolvido' || status == 'Cancelado';
    final podeCancelar = !encerrado &&
        (_admin || (_staff && '${ticket['id_tecnico']}' == meuId) || (ehDono && semTecnico));
    final podeReabrir = encerrado && (_admin || (_staff && '${ticket['id_tecnico']}' == meuId) || ehDono);

    final sla = calcularSla(ticket);
    final slaResposta = calcularSlaPrimeiraResposta(ticket);
    final pendente = status == 'Aguardando Usuário' || status == 'Aguardando Fornecedor';
    final podeEsperar = podeGerir && !encerrado;
    final podeEncaminhar = _staff && !encerrado && (semTecnico || podeGerir);
    final nomeCliente = _nomes['${ticket['id_cliente']}'] ?? '...';
    final idTecnico = ticket['id_tecnico'];
    final nomeTecnico =
        idTecnico == null ? 'Por atribuir' : (_nomes['$idTecnico'] ?? '...');

    return Scaffold(
      backgroundColor: context.cSuperficie,
      appBar: AppBar(
        backgroundColor: context.cSuperficie,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.cTexto),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Chamado ${codigoTicket(ticket['id'])}',
          style: TextStyle(
            color: context.cTexto,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Menu de opções: ações de exceção
          if (podeCancelar || podeReabrir || podeEsperar || _staff)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: context.cTexto),
              tooltip: 'Opções',
              enabled: !_acaoEmCurso,
              onSelected: (v) => _aoEscolherMenu(v, ticket),
              itemBuilder: (_) => [
                if (podeEsperar && status != 'Aguardando Usuário')
                  const PopupMenuItem(
                    value: 'aguardar_usuario',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_search_outlined, color: Color(0xFF7C3AED)),
                      title: Text('Aguardar utilizador'),
                    ),
                  ),
                if (podeEsperar && status != 'Aguardando Fornecedor')
                  const PopupMenuItem(
                    value: 'aguardar_fornecedor',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.local_shipping_outlined, color: Color(0xFF7C3AED)),
                      title: Text('Aguardar fornecedor'),
                    ),
                  ),
                if (podeEsperar && pendente)
                  const PopupMenuItem(
                    value: 'retomar',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.play_circle_outline, color: Color(0xFF059669)),
                      title: Text('Retomar atendimento'),
                    ),
                  ),
                if (podeEncaminhar)
                  const PopupMenuItem(
                    value: 'definir_equipa',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.groups_outlined),
                      title: Text('Encaminhar para equipa'),
                    ),
                  ),
                if (podeEncaminhar)
                  const PopupMenuItem(
                    value: 'atribuir',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.assignment_ind_outlined),
                      title: Text('Atribuir a técnico'),
                    ),
                  ),
                if (_staff)
                  const PopupMenuItem(
                    value: 'historico',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.history),
                      title: Text('Histórico do chamado'),
                    ),
                  ),
                if (podeCancelar)
                  const PopupMenuItem(
                    value: 'cancelar',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cancel_outlined, color: Color(0xFFE11D48)),
                      title: Text('Cancelar Chamado'),
                    ),
                  ),
                if (podeReabrir)
                  const PopupMenuItem(
                    value: 'reabrir',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.refresh, color: Color(0xFF059669)),
                      title: Text('Reabrir Chamado'),
                    ),
                  ),
              ],
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: context.cBorda,
            height: 1.0,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Secção Superior - Detalhes do Chamado
                  Container(
                    color: context.cSuperficie,
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Título e Badge de Prioridade
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                titulo,
                                style: TextStyle(
                                  color: context.cTexto,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: coresPrioridade.fundo,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                prioridade ?? 'Sem prioridade',
                                style: TextStyle(
                                  color: coresPrioridade.texto,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Metadados (Categoria, Status, Data)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildMetaInfo('CATEGORIA', categoria),
                            _buildMetaInfo(
                              'STATUS',
                              status,
                              statusColor: corDoStatus(status),
                            ),
                            _buildMetaInfo(
                              'ABERTO EM',
                              dataHora(ticket['created_at'] as String?),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildMetaInfo('ABERTO POR', nomeCliente),
                            _buildMetaInfo('TÉCNICO RESPONSÁVEL', nomeTecnico),
                          ],
                        ),
                        if (ticket['id_equipe'] != null) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.groups_outlined, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 6),
                              Text(
                                'Equipa: ${_equipas['${ticket['id_equipe']}'] ?? '...'}',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                        // SLA: prazo de resolução conforme a prioridade
                        if (sla != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: sla.fundo,
                              borderRadius: BorderRadius.circular(12),
                              border: sla.urgente ? Border.all(color: sla.cor) : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(sla.icone, size: 18, color: sla.cor),
                                const SizedBox(width: 8),
                                Text(
                                  'SLA: ${sla.texto}',
                                  style: TextStyle(
                                    color: sla.cor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (podeGerir && prioridade == null && !encerrado) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Defina a prioridade para iniciar a contagem do SLA.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                        ],
                        if (_staff && slaResposta != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: slaResposta.fundo,
                              borderRadius: BorderRadius.circular(12),
                              border: slaResposta.urgente ? Border.all(color: slaResposta.cor) : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(slaResposta.icone, size: 18, color: slaResposta.cor),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    slaResposta.texto,
                                    style: TextStyle(
                                      color: slaResposta.cor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Chamado em espera: mostra o motivo (para todos)
                        if (pendente) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE9FE),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.pause_circle_outline, size: 18, color: Color(0xFF7C3AED)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$status: ${ticket['motivo_pendencia'] ?? ''}',
                                    style: const TextStyle(
                                      color: Color(0xFF5B21B6),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Divider(color: context.cBorda, height: 1),
                        const SizedBox(height: 24),

                        // Descrição
                        const Text(
                          'DESCRIÇÃO',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          descricao,
                          style: TextStyle(
                            color: context.cTexto2,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        // Captura de ecrã anexada ao abrir o chamado
                        if (ticket['anexo_path'] != null) ...[
                          const SizedBox(height: 16),
                          ImagemAnexo(caminho: '${ticket['anexo_path']}', altura: 200),
                        ],

                        // Serviço pedido (respostas do formulário)
                        CartaoServico(ticket: ticket, staff: _staff),
                        // Equipamento vinculado
                        CartaoEquipamento(
                          ticket: ticket,
                          staff: _staff,
                          podeEditar: podeGerir && status != 'Cancelado',
                        ),
                        // Horas de trabalho (só equipa técnica)
                        if (_staff)
                          CartaoHoras(
                            ticket: ticket,
                            podeRegistrar: podeGerir && status != 'Cancelado',
                          ),

                        // Botões de ação (apenas técnicos/admins)
                        if (_staff && status != 'Cancelado' && (semTecnico || podeGerir)) ...[
                          const SizedBox(height: 28),
                          if (podeGerir) ...[
                            _buildClassificacao(ticket),
                            const SizedBox(height: 24),
                          ] else ...[
                            const Text(
                              'Assuma o chamado para definir a categoria e a prioridade.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          _buildBotoesDeAcao(ticket, status),
                        ],
                      ],
                    ),
                  ),

                  // Secção de Interações (Fundo Cinzento)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).scaffoldBackgroundColor,
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Text(
                          'Interações',
                          style: TextStyle(
                            color: context.cTexto,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildComentarios(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Barra de Introdução de Comentário Inferior
          _buildBarraComentario(ticket),
        ],
      ),
    );
  }

  /// O técnico decide a categoria e a prioridade; grava ao escolher.
  Widget _buildClassificacao(Map<String, dynamic> ticket) {
    final id = ticket['id'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildSeletor(
            label: 'CATEGORIA',
            value: ticket['categoria'] as String?,
            opcoes: const ['Hardware', 'Software', 'Rede', 'Outros'],
            onChanged: (v) => _executar(
              () => TicketService.instance.classificar(id, categoria: v),
              'Categoria atualizada.',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSeletor(
            label: 'PRIORIDADE',
            value: ticket['prioridade'] as String?,
            opcoes: const ['Baixa', 'Média', 'Alta'],
            onChanged: (v) => _executar(
              () => TicketService.instance.classificar(id, prioridade: v),
              'Prioridade atualizada.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeletor({
    required String label,
    required String? value,
    required List<String> opcoes,
    required void Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.cSuperficie,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.cBorda),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: Text(
                'Definir',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
              icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
              style: TextStyle(color: context.cTexto, fontSize: 13),
              items: [
                for (final o in opcoes)
                  DropdownMenuItem<String>(value: o, child: Text(o)),
              ],
              onChanged: _acaoEmCurso
                  ? null
                  : (v) {
                      if (v != null && v != value) onChanged(v);
                    },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBotoesDeAcao(Map<String, dynamic> ticket, String status) {
    final semTecnico = ticket['id_tecnico'] == null;
    final String rotulo;
    if (semTecnico) {
      rotulo = 'Assumir Chamado';
    } else if (status == 'Resolvido') {
      rotulo = 'Reabrir Chamado';
    } else {
      rotulo = 'Resolver Chamado';
    }

    final principal = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF042C5C),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
      onPressed: _acaoEmCurso ? null : () => _acaoPrincipal(ticket),
      child: _acaoEmCurso
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Text(
              rotulo,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
    );

    // Por assumir: só a ação de assumir.
    if (semTecnico) {
      return SizedBox(width: double.infinity, child: principal);
    }

    return Row(
      children: [
        Expanded(child: principal),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: context.cBorda),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: (_acaoEmCurso || status == 'Resolvido')
                ? null
                : () => _transferir(ticket),
            child: Text(
              'Transferir',
              style: TextStyle(
                color: context.cTexto,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComentarios() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _comentariosStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Não foi possível carregar as interações.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final lista = snapshot.data!;
        if (!identical(lista, _ultimosComentarios)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _aoReceberComentarios(lista);
          });
        }
        if (lista.isEmpty) {
          return const Text(
            'Ainda não há interações neste chamado.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
          );
        }
        final ehDono = '${_inicial?['id_cliente']}' == AuthService.instance.utilizadorAtual?.id;
        return Column(
          children: [
            for (final c in lista)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: switch (c['tipo']) {
                  'sistema' => _buildAvisoSistema('${c['mensagem']}', c['created_at'] as String?),
                  'csat' => _buildCsat(c, ehDono),
                  _ => _buildInteractionCard(
                      name: '${c['autor_nome'] ?? 'Utilizador'}',
                      role: _rotuloRole(c['autor_role'] as String?),
                      roleColor: c['autor_role'] == 'cliente' || c['autor_role'] == null
                          ? context.cBorda
                          : const Color(0xFFE0E7FF),
                      roleTextColor: c['autor_role'] == 'cliente' || c['autor_role'] == null
                          ? context.cTexto2
                          : const Color(0xFF3730A3),
                      time: dataHora(c['created_at'] as String?),
                      message: '${c['mensagem']}',
                      anexoPath: c['anexo_path'] as String?,
                      interno: c['tipo'] == 'nota_interna',
                    ),
                },
              ),
          ],
        );
      },
    );
  }

  /// Aviso automático do sistema (ex.: reaberto automaticamente).
  Widget _buildAvisoSistema(String texto, String? iso) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: context.cFundoSuave,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    texto,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              dataHora(iso),
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  /// Pedido de avaliação (CSAT): 1 a 5 estrelas para o cliente.
  Widget _buildCsat(Map<String, dynamic> c, bool ehDono) {
    final nota = (c['csat_nota'] as num?)?.toInt();
    final id = c['id'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFBBF24)),
      ),
      child: Column(
        children: [
          Text(
            '${c['mensagem']}',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cTexto, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '$i ${i == 1 ? 'estrela' : 'estrelas'}',
                  icon: Icon(
                    (nota != null && i <= nota) ? Icons.star : Icons.star_border,
                    color: const Color(0xFFF59E0B),
                    size: 34,
                  ),
                  // só o cliente, e só enquanto ainda não avaliou
                  onPressed: (ehDono && nota == null && !_acaoEmCurso) ? () => _avaliar(id, i) : null,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            nota != null
                ? 'Avaliação: $nota/5'
                : (ehDono ? 'Toque numa estrela para avaliar.' : 'A aguardar a avaliação do cliente.'),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraComentario(Map<String, dynamic> ticket) {
    final status = '${ticket['status']}';
    final ehDono = '${ticket['id_cliente']}' == AuthService.instance.utilizadorAtual?.id;
    // Resolvido: só o cliente pode escrever (e isso reabre o chamado).
    // Cancelado: ninguém, até ser reaberto.
    final bloqueado = status == 'Cancelado' || (status == 'Resolvido' && !ehDono);
    final reabreAoEscrever = status == 'Resolvido' && ehDono;
    final nota = _staff && _notaInterna;
    final escuro = Theme.of(context).brightness == Brightness.dark;

    final hint = bloqueado
        ? (status == 'Cancelado'
            ? 'Chamado cancelado. Reabra-o para conversar.'
            : 'Chamado resolvido. Reabra-o para conversar.')
        : (nota ? 'Escreva uma nota interna...' : 'Escreva um comentário...');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: nota
            ? (escuro ? const Color(0xFF3B2F0B) : const Color(0xFFFFFBEB))
            : context.cSuperficie,
        border: Border(top: BorderSide(color: context.cBorda)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reabreAoEscrever)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Color(0xFFD97706)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Este chamado está resolvido. Se enviar uma mensagem, ele será reaberto.',
                        style: TextStyle(color: Color(0xFFD97706), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            // Pré-visualização da imagem escolhida
            if (_imagemBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(_imagemBytes!, height: 84, width: 84, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: -8,
                        right: -8,
                        child: GestureDetector(
                          onTap: _enviando ? null : _removerImagem,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                // Anexar imagem da galeria
                IconButton(
                  icon: Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade600),
                  tooltip: 'Anexar imagem',
                  onPressed: (_enviando || bloqueado) ? null : _escolherImagem,
                ),
                // Só técnicos: respostas rápidas e nota interna
                if (_staff) ...[
                  IconButton(
                    icon: const Icon(Icons.bolt, color: Color(0xFFD97706)),
                    tooltip: 'Respostas rápidas',
                    onPressed: (_enviando || bloqueado) ? null : _abrirMacros,
                  ),
                  IconButton(
                    icon: Icon(
                      nota ? Icons.lock : Icons.lock_open_outlined,
                      color: nota ? const Color(0xFFD97706) : Colors.grey.shade600,
                    ),
                    tooltip: nota ? 'Nota interna (só a equipa vê)' : 'Mensagem visível ao cliente',
                    onPressed: (_enviando || bloqueado)
                        ? null
                        : () => setState(() => _notaInterna = !_notaInterna),
                  ),
                ],
                Expanded(
                  child: TextField(
                    controller: _comentarioCtrl,
                    enabled: !bloqueado,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _enviarComentario(),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: bloqueado ? Colors.grey.shade400 : const Color(0xFF042C5C),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: (_enviando || bloqueado) ? null : _enviarComentario,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Widget construtor para a linha de metadados
  Widget _buildMetaInfo(String label, String value, {Color? statusColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (statusColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              value,
              style: TextStyle(
                color: context.cTexto,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Widget construtor para os cartões de interação (Chat)
  Widget _buildInteractionCard({
    required String name,
    required String role,
    required Color roleColor,
    required Color roleTextColor,
    required String time,
    required String message,
    String? anexoPath,
    bool interno = false,
  }) {
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: interno
            ? (escuro ? const Color(0xFF3B2F0B) : const Color(0xFFFFFBEB))
            : context.cSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: interno ? const Color(0xFFFCD34D) : context.cBorda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (interno) ...[
            const Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: Color(0xFFD97706)),
                SizedBox(width: 6),
                Text(
                  'NOTA INTERNA · só a equipa técnica vê',
                  style: TextStyle(
                    color: Color(0xFFD97706),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.cTexto,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: roleColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        role,
                        style: TextStyle(
                          color: roleTextColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                time,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (message.trim().isNotEmpty)
            Text(
              message,
              style: TextStyle(
                color: context.cTexto2,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          if (anexoPath != null) ...[
            if (message.trim().isNotEmpty) const SizedBox(height: 12),
            ImagemAnexo(caminho: anexoPath),
          ],
        ],
      ),
    );
  }
}

/// Diálogo que pede o motivo (obrigatório) de uma pendência.
class _DialogoMotivo extends StatefulWidget {
  final String titulo;
  const _DialogoMotivo({required this.titulo});

  @override
  State<_DialogoMotivo> createState() => _DialogoMotivoState();
}

class _DialogoMotivoState extends State<_DialogoMotivo> {
  final _c = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _confirmar() {
    final t = _c.text.trim();
    if (t.isEmpty) {
      setState(() => _erro = 'Indique o motivo.');
      return;
    }
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(
          labelText: 'Motivo (o SLA fica em pausa)',
          errorText: _erro,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        TextButton(onPressed: _confirmar, child: const Text('Confirmar')),
      ],
    );
  }
}
