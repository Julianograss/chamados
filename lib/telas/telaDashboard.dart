import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../servicos/auth_service.dart';
import '../servicos/configuracoes.dart';
import '../servicos/equipas_service.dart';
import '../servicos/formatadores.dart';
import '../servicos/notificacao_service.dart';
import '../servicos/ticket_service.dart';
import '../tema.dart';

enum _Periodo { qualquer, hoje, semana, mes }

const _semValor = '__sem__'; // "Por definir" nos filtros de categoria/prioridade

/// Filtros avançados escolhidos no Bottom Sheet (cruzam-se entre si e com a busca).
class _Filtros {
  final int aba; // estado (índice da aba da Dashboard)
  final String? categoria;
  final String? prioridade;
  final _Periodo periodo;
  final bool soMeus; // só técnico: chamados que assumi
  final String? equipa; // id da equipa, ou _semValor

  const _Filtros({
    required this.aba,
    this.categoria,
    this.prioridade,
    this.periodo = _Periodo.qualquer,
    this.soMeus = false,
    this.equipa,
  });

  /// Quantos filtros (além do estado) estão ativos.
  int get ativos =>
      (categoria != null ? 1 : 0) +
      (prioridade != null ? 1 : 0) +
      (periodo != _Periodo.qualquer ? 1 : 0) +
      (soMeus ? 1 : 0) +
      (equipa != null ? 1 : 0);
}

class telaDashboard extends StatefulWidget {
  const telaDashboard({super.key});

  @override
  State<telaDashboard> createState() => _telaDashboardState();
}

class _telaDashboardState extends State<telaDashboard> {
  static const _abas = ['Abertos', 'Em\nAndamento', 'Resolvidos', 'Cancelados'];
  // "Em Andamento" inclui os chamados pendentes (Aguardando Usuário/Fornecedor).
  static const _statusesDaAba = <Set<String>>[
    {'Aberto'},
    {'Em Andamento', 'Aguardando Usuário', 'Aguardando Fornecedor'},
    {'Resolvido'},
    {'Cancelado'},
  ];

  // Sino: quantidade de notificações por ler
  late final Stream<int> _naoLidas = NotificacaoService.instance.naoLidas();

  // O stream é criado uma única vez (depois de saber a role) para não
  // reabrir a ligação a cada setState.
  Stream<List<Map<String, dynamic>>>? _chamados;
  bool _ehStaff = false;

  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    _iniciar();
    _carregarEquipas();
    // Atualiza as contagens do SLA sem esperar por novos dados do servidor.
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _carregarEquipas() async {
    try {
      final lista = await EquipasService.instance.listar();
      if (mounted) setState(() => _equipas = lista);
    } catch (_) {}
  }

  String? _nomeEquipa(dynamic id) {
    if (id == null) return null;
    for (final e in _equipas) {
      if ('${e['id']}' == '$id') return '${e['nome']}';
    }
    return null;
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  Future<void> _iniciar() async {
    var staff = false;
    String? aviso;
    try {
      final perfil = await AuthService.instance.perfilAtual();
      if (perfil == null) {
        aviso = 'O seu perfil não existe na tabela users. '
            'Execute o schema.sql novamente no Supabase.';
      }
      if (perfil != null && perfil['ativo'] == false) {
        // Conta desativada pelo administrador: termina a sessão.
        await AuthService.instance.sair();
        return;
      }
      final role = perfil?['role'];
      staff = role == 'tecnico' || role == 'admin';
    } catch (e) {
      // Sem perfil legível: trata como cliente (vê apenas os seus chamados).
      aviso = 'Não foi possível ler o seu perfil'
          '${kDebugMode ? ': $e' : '.'}';
    }
    if (!mounted) return;
    setState(() {
      _ehStaff = staff;
      _chamados = TicketService.instance.chamados(todos: staff);
    });
    if (aviso != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(aviso),
          backgroundColor: const Color(0xFFE11D48),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  int _abaAtiva = 0;
  String _busca = '';
  bool _ordenarPorPrioridade = false;

  // Filtros avançados (Bottom Sheet)
  String? _fCategoria;
  String? _fPrioridade;
  _Periodo _fPeriodo = _Periodo.qualquer;
  bool _fSoMeus = false;
  String? _fEquipa;
  List<Map<String, dynamic>> _equipas = [];

  // Para avisar quando algo muda (Configurações > Notificações)
  List<Map<String, dynamic>>? _ultimaLista;

  _Filtros get _filtros => _Filtros(
        aba: _abaAtiva,
        categoria: _fCategoria,
        prioridade: _fPrioridade,
        periodo: _fPeriodo,
        soMeus: _fSoMeus,
        equipa: _fEquipa,
      );

  int _pesoPrioridade(String? p) =>
      p == 'Alta' ? 3 : (p == 'Média' ? 2 : (p == 'Baixa' ? 1 : 0));

  /// Minúsculas e sem acentos, para a busca ignorar "ç", "ã", etc.
  static String _normalizar(String texto) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final sb = StringBuffer();
    for (final c in texto.toLowerCase().split('')) {
      final i = de.indexOf(c);
      sb.write(i >= 0 ? para[i] : c);
    }
    return sb.toString();
  }

  /// Busca em tempo real: pelo número ("1024", "#1024", "TK-1024") ou por
  /// palavras do título (todas as palavras têm de aparecer).
  bool _combinaBusca(Map<String, dynamic> t, String termo) {
    if (termo.isEmpty) return true;
    final titulo = _normalizar('${t['titulo']}');
    final palavras = termo.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (palavras.every(titulo.contains)) return true;

    final numero = termo.replaceAll('#', '').replaceFirst(RegExp(r'^tk-?'), '').trim();
    if (numero.isNotEmpty && RegExp(r'^\d+$').hasMatch(numero)) {
      return '${t['id']}'.contains(numero);
    }
    return false;
  }

  DateTime? _inicioDoPeriodo() {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    switch (_fPeriodo) {
      case _Periodo.hoje:
        return hoje;
      case _Periodo.semana:
        return hoje.subtract(Duration(days: hoje.weekday - 1)); // segunda-feira
      case _Periodo.mes:
        return DateTime(agora.year, agora.month, 1);
      case _Periodo.qualquer:
        return null;
    }
  }

  bool _combinaValor(String? valor, String? filtro) {
    if (filtro == null) return true;
    return filtro == _semValor ? valor == null : valor == filtro;
  }

  List<Map<String, dynamic>> _filtrar(List<Map<String, dynamic>> todos) {
    final termo = _normalizar(_busca.trim());
    final desde = _inicioDoPeriodo();
    final meuId = AuthService.instance.utilizadorAtual?.id;
    final lista = todos.where((t) {
      if (!_statusesDaAba[_abaAtiva].contains(t['status'])) return false;
      if (!_combinaBusca(t, termo)) return false;
      if (!_combinaValor(t['categoria'] as String?, _fCategoria)) return false;
      if (!_combinaValor(t['prioridade'] as String?, _fPrioridade)) return false;
      if (_fSoMeus && '${t['id_tecnico']}' != meuId) return false;
      if (_fEquipa != null &&
          !(_fEquipa == _semValor ? t['id_equipe'] == null : '${t['id_equipe']}' == _fEquipa)) {
        return false;
      }
      if (desde != null) {
        final criado = DateTime.tryParse('${t['created_at']}')?.toLocal();
        if (criado == null || criado.isBefore(desde)) return false;
      }
      return true;
    }).toList();
    if (_ordenarPorPrioridade) {
      lista.sort((a, b) =>
          _pesoPrioridade(b['prioridade']).compareTo(_pesoPrioridade(a['prioridade'])));
    }
    return lista;
  }

  Future<void> _abrirFiltros() async {
    final novo = await showModalBottomSheet<_Filtros>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cSuperficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FiltrosSheet(inicial: _filtros, ehStaff: _ehStaff, abas: _abas, equipas: _equipas),
    );
    if (novo == null || !mounted) return;
    setState(() {
      _abaAtiva = novo.aba;
      _fCategoria = novo.categoria;
      _fPrioridade = novo.prioridade;
      _fPeriodo = novo.periodo;
      _fSoMeus = novo.soMeus;
      _fEquipa = novo.equipa;
    });
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(texto), backgroundColor: const Color(0xFF0066FF)),
      );
  }

  /// Compara com a lista anterior e avisa (se as notificações estiverem ativas).
  void _verificarMudancas(List<Map<String, dynamic>> nova) {
    final antiga = _ultimaLista;
    _ultimaLista = nova;
    if (antiga == null || !Configuracoes.instance.notificacoes.value) return;
    final meuId = AuthService.instance.utilizadorAtual?.id;
    final antigos = {for (final t in antiga) '${t['id']}': t};

    for (final t in nova) {
      final antes = antigos['${t['id']}'];
      final codigo = codigoTicket(t['id']);
      if (antes == null) {
        if (!_ehStaff) continue; // o cliente já sabe que abriu o chamado
        if (t['id_tecnico'] == null) {
          _aviso('Novo chamado $codigo por assumir.');
        } else if ('${t['id_tecnico']}' == meuId) {
          _aviso('O chamado $codigo foi transferido para si.');
        }
        return;
      }
      // Cliente comentou num chamado resolvido: voltou a "Aberto" (alerta o técnico)
      if (_ehStaff &&
          antes['status'] == 'Resolvido' &&
          (t['status'] == 'Aberto' || t['status'] == 'Em Andamento') &&
          '${t['id_tecnico']}' == meuId) {
        _aviso('O cliente reabriu o chamado $codigo com uma nova mensagem.');
        return;
      }
      if (!_ehStaff && antes['status'] != t['status']) {
        if (antes['status'] == 'Aberto' && t['status'] == 'Em Andamento') {
          _aviso('O chamado $codigo foi assumido por um técnico.');
          return;
        }
        if (t['status'] == 'Resolvido') {
          _aviso('O chamado $codigo foi resolvido.');
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fundo branco no bottomNavigationBar para o botão inferior[cite: 2]
      bottomNavigationBar: Container(
        color: context.cSuperficie,
        padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 32),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF062A5A),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          onPressed: () => Navigator.of(context).pushNamed('/new_ticket'),
          // Botão "Novo Chamado" na parte inferior[cite: 2]
          child: const Text(
            'Novo Chamado',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Cabeçalho Escuro[cite: 2]
          Container(
            padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
            decoration: const BoxDecoration(
              color: Color(0xFF041C3B),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Título "BlueDesk"[cite: 2]
                        const Text(
                          'BlueDesk',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Subtítulo "Central de Suporte"[cite: 2]
                        Text(
                          'Central de Suporte',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    // Base de conhecimento
                    GestureDetector(
                      onTap: () => Navigator.of(context).pushNamed('/conhecimento'),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.menu_book_outlined, color: Colors.white, size: 24),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Sino: central de notificações (com contador de por ler)
                    StreamBuilder<int>(
                      stream: _naoLidas,
                      builder: (context, snap) {
                        final n = snap.data ?? 0;
                        return GestureDetector(
                          onTap: () => Navigator.of(context).pushNamed('/notificacoes'),
                          child: Badge(
                            isLabelVisible: n > 0,
                            label: Text(n > 99 ? '99+' : '$n'),
                            backgroundColor: const Color(0xFFE11D48),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_none,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    // Ícone de Perfil[cite: 2]
                    GestureDetector(
                      onTap: () => Navigator.of(context).pushNamed('/perfil'),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    // Barra de Pesquisa "Buscar chamados..."[cite: 2]
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: context.cSuperficie,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          onChanged: (v) => setState(() => _busca = v),
                          decoration: InputDecoration(
                            hintText: 'Buscar chamados...',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.grey.shade600,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Botão de Filtro Azul: abre os filtros avançados
                    GestureDetector(
                      onTap: _abrirFiltros,
                      child: Badge(
                        isLabelVisible: _filtros.ativos > 0,
                        label: Text('${_filtros.ativos}'),
                        backgroundColor: const Color(0xFFE11D48),
                        child: Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0066FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.tune,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chamados,
              builder: (context, snapshot) {
                final carregando = _chamados == null ||
                    (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData);
                final dados = snapshot.data;
                if (dados != null && !identical(dados, _ultimaLista)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _verificarMudancas(dados);
                  });
                }
                final lista = _filtrar(dados ?? const []);

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Separadores (Tabs) "Abertos", "Em Andamento", "Resolvidos"
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: context.cSuperficie,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.cBorda),
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < _abas.length; i++)
                            Expanded(
                              child: _buildTab(
                                title: _abas[i],
                                isActive: _abaAtiva == i,
                                onTap: () => setState(() => _abaAtiva = i),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Cabeçalho da Lista "Meus Chamados (n)" e "Prioridade"
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_ehStaff && _abaAtiva == 0 ? 'Por assumir' : 'Meus Chamados'} (${lista.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(
                              () => _ordenarPorPrioridade = !_ordenarPorPrioridade),
                          child: Row(
                            children: [
                              Icon(
                                Icons.filter_list,
                                size: 16,
                                color: _ordenarPorPrioridade
                                    ? const Color(0xFF0066FF)
                                    : Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Prioridade',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _ordenarPorPrioridade
                                      ? const Color(0xFF0066FF)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (carregando)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.hasError)
                      _buildMensagemVazia(
                        icon: Icons.cloud_off_outlined,
                        texto:
                            'Não foi possível carregar os chamados.\nVerifique a ligação e tente novamente.'
                            '${kDebugMode ? '\n\n${snapshot.error}' : ''}',
                      )
                    else if (lista.isEmpty)
                      _buildMensagemVazia(
                        icon: Icons.inbox_outlined,
                        texto: (_busca.trim().isNotEmpty || _filtros.ativos > 0)
                            ? 'Nenhum chamado encontrado com a pesquisa e os filtros atuais.'
                            : 'Não tem chamados nesta categoria.',
                      )
                    else
                      for (final t in lista) ...[
                        _buildTicketCard(
                          ticketId: codigoTicket(t['id']),
                          priority: (t['prioridade'] as String?) ?? 'Sem prioridade',
                          priorityColor: coresDaPrioridade(t['prioridade']).texto,
                          priorityBg: coresDaPrioridade(t['prioridade']).fundo,
                          title: '${t['titulo']}',
                          time: tempoDecorrido(t['created_at'] as String?),
                          sla: calcularSla(t),
                          equipa: _nomeEquipa(t['id_equipe']),
                          slaResposta: (_ehStaff && t['primeira_resposta_em'] == null)
                              ? calcularSlaPrimeiraResposta(t)
                              : null,
                          status: '${t['status']}',
                          statusColor: corDoStatus(t['status'] as String?),
                          onTap: () => Navigator.of(context)
                              .pushNamed('/ticket_details', arguments: t),
                        ),
                        const SizedBox(height: 16),
                      ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMensagemVazia({required IconData icon, required String texto}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 44, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }

  // Widget para as abas de navegação[cite: 2]
  Widget _buildTab({
    required String title,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ?  context.cBorda : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ?  context.cTexto : const Color(0xFF64748B),
              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  // Widget para o cartão de chamado[cite: 2]
  Widget _chipSla(Sla sla) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: sla.fundo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sla.icone, size: 14, color: sla.cor),
          const SizedBox(width: 6),
          Text(
            sla.texto,
            style: TextStyle(color: sla.cor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketCard({
    required String ticketId,
    required String priority,
    required Color priorityColor,
    required Color priorityBg,
    required String title,
    required String time,
    Sla? sla,
    Sla? slaResposta,
    String? equipa,
    required String status,
    required Color statusColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (sla?.urgente ?? false) ? sla!.cor.withOpacity(0.5) : context.cBorda,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.cFundoSuave,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  ticketId,
                  style: TextStyle(
                    color: context.cTexto2,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: priorityBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  priority,
                  style: TextStyle(
                    color: priorityColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: context.cTexto,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                time,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          // SLA: contagem do prazo; vermelho com fogo quando está a esgotar
          if (sla != null || slaResposta != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (sla != null) _chipSla(sla),
                if (slaResposta != null) _chipSla(slaResposta),
              ],
            ),
          ],
          if (equipa != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.groups_outlined, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text('Equipa: $equipa', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Divider(color: context.cBorda, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status,
                    style: TextStyle(
                      color: context.cTexto2,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    ));
  }
}

/// Bottom Sheet com os filtros avançados. Devolve os filtros escolhidos
/// (ou null se for fechado sem aplicar).
class _FiltrosSheet extends StatefulWidget {
  final _Filtros inicial;
  final bool ehStaff;
  final List<String> abas;
  final List<Map<String, dynamic>> equipas;
  const _FiltrosSheet({
    required this.inicial,
    required this.ehStaff,
    required this.abas,
    required this.equipas,
  });

  @override
  State<_FiltrosSheet> createState() => _FiltrosSheetState();
}

class _FiltrosSheetState extends State<_FiltrosSheet> {
  late int _aba = widget.inicial.aba;
  late String? _categoria = widget.inicial.categoria;
  late String? _prioridade = widget.inicial.prioridade;
  late _Periodo _periodo = widget.inicial.periodo;
  late bool _soMeus = widget.inicial.soMeus;
  late String? _equipa = widget.inicial.equipa;

  static const _categorias = ['Hardware', 'Software', 'Rede', 'Outros'];
  static const _prioridades = ['Alta', 'Média', 'Baixa'];

  Widget _grupo(String titulo, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  Widget _chip(String rotulo, bool ativo, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(rotulo),
      selected: ativo,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF0066FF),
      labelStyle: TextStyle(
        color: ativo ? Colors.white : context.cTexto,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      showCheckmark: false,
    );
  }

  /// Escolher o mesmo valor outra vez desmarca (volta a "todos").
  Widget _chipOpcional(String rotulo, String valor, String? atual, void Function(String?) set) {
    return _chip(rotulo, atual == valor, () => setState(() => set(atual == valor ? null : valor)));
  }

  @override
  Widget build(BuildContext context) {
    final nomesPeriodo = {
      _Periodo.hoje: 'Hoje',
      _Periodo.semana: 'Esta semana',
      _Periodo.mes: 'Este mês',
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Filtros',
                    style: TextStyle(
                      color: context.cTexto,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _categoria = null;
                      _prioridade = null;
                      _periodo = _Periodo.qualquer;
                      _soMeus = false;
                      _equipa = null;
                    }),
                    child: const Text('Limpar'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _grupo('ESTADO', [
                for (var i = 0; i < widget.abas.length; i++)
                  _chip(widget.abas[i].replaceAll('\n', ' '), _aba == i, () => setState(() => _aba = i)),
              ]),
              _grupo('CATEGORIA', [
                for (final c in _categorias)
                  _chipOpcional(c, c, _categoria, (v) => _categoria = v),
                _chipOpcional('Por definir', _semValor, _categoria, (v) => _categoria = v),
              ]),
              _grupo('PRIORIDADE', [
                for (final p in _prioridades)
                  _chipOpcional(p, p, _prioridade, (v) => _prioridade = v),
                _chipOpcional('Por definir', _semValor, _prioridade, (v) => _prioridade = v),
              ]),
              if (widget.equipas.isNotEmpty)
                _grupo('EQUIPA / FILA', [
                  for (final e in widget.equipas)
                    _chipOpcional('${e['nome']}', '${e['id']}', _equipa, (v) => _equipa = v),
                  _chipOpcional('Sem equipa', _semValor, _equipa, (v) => _equipa = v),
                ]),
              _grupo('CRIADOS', [
                for (final e in nomesPeriodo.entries)
                  _chip(
                    e.value,
                    _periodo == e.key,
                    () => setState(() => _periodo = _periodo == e.key ? _Periodo.qualquer : e.key),
                  ),
              ]),
              if (widget.ehStaff)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _soMeus,
                  onChanged: (v) => setState(() => _soMeus = v),
                  title: const Text('Só os que assumi', style: TextStyle(fontSize: 14)),
                  activeColor: const Color(0xFF0066FF),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF062A5A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(context).pop(
                    _Filtros(
                      aba: _aba,
                      categoria: _categoria,
                      prioridade: _prioridade,
                      periodo: _periodo,
                      soMeus: _soMeus,
                      equipa: _equipa,
                    ),
                  ),
                  child: const Text(
                    'Aplicar filtros',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
