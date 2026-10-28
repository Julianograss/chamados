import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/admin_service.dart';
import '../servicos/auth_service.dart';
import '../servicos/formatadores.dart';
import '../servicos/inventario_service.dart';
import '../servicos/ticket_service.dart';
import '../tema.dart';

String _dataCurta(dynamic iso) {
  final d = DateTime.tryParse('$iso');
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

IconData _iconeDoTipo(String? tipo) {
  switch (tipo) {
    case 'Computador':
      return Icons.desktop_windows_outlined;
    case 'Notebook':
      return Icons.laptop_mac;
    case 'Monitor':
      return Icons.monitor;
    case 'Impressora':
      return Icons.print_outlined;
    case 'Roteador':
      return Icons.router_outlined;
    default:
      return Icons.devices_other;
  }
}

/// Número de chamados nos últimos 90 dias a partir do qual o equipamento é
/// considerado com "defeitos recorrentes".
const limiteRecorrente = 3;

/// Lista do inventário de equipamentos de TI.
class telaInventario extends StatefulWidget {
  const telaInventario({super.key});

  @override
  State<telaInventario> createState() => _telaInventarioState();
}

class _telaInventarioState extends State<telaInventario> {
  List<Map<String, dynamic>> _assets = const [];
  Map<String, Map<String, dynamic>> _stats = const {};
  Map<String, String> _nomes = const {};
  bool _carregando = true;
  bool _erro = false;
  String _busca = '';
  String? _tipo;
  String? _situacao;
  bool _soRecorrentes = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = false;
    });
    try {
      final assets = await InventarioService.instance.listar();
      var stats = <String, Map<String, dynamic>>{};
      var nomes = <String, String>{};
      try {
        stats = await InventarioService.instance.estatisticas();
        final us = await AdminService.instance.listarUsuarios();
        nomes = {for (final u in us) '${u['id']}': '${u['nome']}'};
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _stats = stats;
        _nomes = nomes;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erro = true;
        });
      }
    }
  }

  int _recentes(Map<String, dynamic> a) => (_stats['${a['id']}']?['recentes'] as num?)?.toInt() ?? 0;
  int _total(Map<String, dynamic> a) => (_stats['${a['id']}']?['total'] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get _filtrados {
    final termo = _normalizar(_busca.trim());
    final lista = _assets.where((a) {
      if (_tipo != null && a['tipo'] != _tipo) return false;
      if (_situacao != null && a['situacao'] != _situacao) return false;
      if (_soRecorrentes && _recentes(a) < limiteRecorrente) return false;
      if (termo.isEmpty) return true;
      final texto = _normalizar(
        '${a['patrimonio']} ${a['numero_serie'] ?? ''} ${a['modelo'] ?? ''} ${a['setor'] ?? ''} '
        '${a['localizacao'] ?? ''} ${_nomes['${a['id_responsavel']}'] ?? ''}',
      );
      return termo.split(RegExp(r'\s+')).every(texto.contains);
    }).toList();
    if (_soRecorrentes) lista.sort((a, b) => _recentes(b).compareTo(_recentes(a)));
    return lista;
  }

  static String _normalizar(String t) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final sb = StringBuffer();
    for (final c in t.toLowerCase().split('')) {
      final i = de.indexOf(c);
      sb.write(i >= 0 ? para[i] : c);
    }
    return sb.toString();
  }

  Future<void> _abrir([Map<String, dynamic>? asset]) async {
    final mudou = await Navigator.of(context).pushNamed('/asset', arguments: asset);
    if (mudou == true) _carregar();
  }

  Widget _chip(String rotulo, bool ativo, VoidCallback onTap) => ChoiceChip(
        label: Text(rotulo),
        selected: ativo,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0xFF0066FF),
        showCheckmark: false,
        labelStyle: TextStyle(
          color: ativo ? Colors.white : context.cTexto,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    final recorrentes = _assets.where((a) => _recentes(a) >= limiteRecorrente).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventário de equipamentos', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.cBorda, height: 1),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0066FF),
        foregroundColor: Colors.white,
        onPressed: () => _abrir(),
        icon: const Icon(Icons.add),
        label: const Text('Novo equipamento'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro
              ? Center(child: TextButton(onPressed: _carregar, child: const Text('Erro ao carregar. Tentar novamente')))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
                    children: [
                      TextField(
                        onChanged: (v) => setState(() => _busca = v),
                        decoration: InputDecoration(
                          hintText: 'Pesquisar patrimônio, série, modelo, setor...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: context.cSuperficie,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: context.cBorda),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final t in InventarioService.tipos)
                          _chip(t, _tipo == t, () => setState(() => _tipo = _tipo == t ? null : t)),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final s in InventarioService.situacoes)
                          _chip(s, _situacao == s, () => setState(() => _situacao = _situacao == s ? null : s)),
                        FilterChip(
                          avatar: const Icon(Icons.local_fire_department, size: 16, color: Color(0xFFE11D48)),
                          label: Text('Defeitos recorrentes ($recorrentes)'),
                          selected: _soRecorrentes,
                          onSelected: (v) => setState(() => _soRecorrentes = v),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Text(
                        '${lista.length} ${lista.length == 1 ? 'equipamento' : 'equipamentos'}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (lista.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('Nenhum equipamento encontrado.')),
                        ),
                      for (final a in lista) _tile(a),
                    ],
                  ),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> a) {
    final recentes = _recentes(a);
    final recorrente = recentes >= limiteRecorrente;
    final garantia = DateTime.tryParse('${a['garantia_ate']}');
    final emGarantia = garantia != null && !garantia.isBefore(DateTime.now());
    final responsavel = _nomes['${a['id_responsavel']}'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.cSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: recorrente ? const Color(0xFFE11D48).withOpacity(0.5) : context.cBorda),
      ),
      child: ListTile(
        onTap: () => _abrir(a),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFDBEAFE),
          child: Icon(_iconeDoTipo(a['tipo'] as String?), color: const Color(0xFF1D4ED8)),
        ),
        title: Text(
          '${a['patrimonio']}${(a['modelo'] ?? '').toString().isEmpty ? '' : ' · ${a['modelo']}'}',
          style: TextStyle(color: context.cTexto, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([
              '${a['tipo']}',
              if (responsavel != null) responsavel,
              if ((a['setor'] ?? '').toString().isNotEmpty) '${a['setor']}',
            ].join(' · ')),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _selo('${a['situacao']}', context.cBorda, context.cTexto2),
              if (garantia != null)
                _selo(
                  emGarantia ? 'Garantia até ${_dataCurta(a['garantia_ate'])}' : 'Fora da garantia',
                  emGarantia ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                  emGarantia ? const Color(0xFF059669) : const Color(0xFFD97706),
                ),
              if (recorrente)
                _selo('🔥 $recentes chamados em 90 dias', const Color(0xFFFFE4E6), const Color(0xFFE11D48)),
            ]),
          ],
        ),
        isThreeLine: true,
        trailing: Text('${_total(a)}', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _selo(String t, Color fundo, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold)),
      );
}

/// Ficha de um equipamento: criar/editar e ver o histórico de problemas.
class telaAsset extends StatefulWidget {
  const telaAsset({super.key});

  @override
  State<telaAsset> createState() => _telaAssetState();
}

class _telaAssetState extends State<telaAsset> {
  final _patrimonio = TextEditingController();
  final _serie = TextEditingController();
  final _modelo = TextEditingController();
  final _setor = TextEditingController();
  final _local = TextEditingController();
  final _obs = TextEditingController();
  String _tipo = 'Computador';
  String _situacao = 'Em uso';
  String? _responsavel;
  DateTime? _garantia;

  Map<String, dynamic>? _original;
  List<Map<String, dynamic>> _usuarios = const [];
  List<Map<String, dynamic>> _chamados = const [];
  bool _iniciado = false;
  bool _admin = false;
  bool _aGuardar = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final a = Map<String, dynamic>.from(args);
      _original = a;
      _patrimonio.text = '${a['patrimonio'] ?? ''}';
      _serie.text = '${a['numero_serie'] ?? ''}';
      _modelo.text = '${a['modelo'] ?? ''}';
      _setor.text = '${a['setor'] ?? ''}';
      _local.text = '${a['localizacao'] ?? ''}';
      _obs.text = '${a['observacoes'] ?? ''}';
      _tipo = '${a['tipo']}';
      _situacao = '${a['situacao']}';
      _responsavel = a['id_responsavel'] as String?;
      _garantia = DateTime.tryParse('${a['garantia_ate']}');
    }
    _carregarExtras();
  }

  @override
  void dispose() {
    for (final c in [_patrimonio, _serie, _modelo, _setor, _local, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarExtras() async {
    try {
      final perfil = await AuthService.instance.perfilAtual();
      final admin = perfil?['role'] == 'admin';
      final usuarios = await AdminService.instance.listarUsuarios();
      var chamados = <Map<String, dynamic>>[];
      if (_original != null) {
        chamados = await InventarioService.instance.chamadosDoAsset(_original!['id']);
      }
      if (!mounted) return;
      setState(() {
        _admin = admin;
        _usuarios = usuarios.where((u) => u['ativo'] != false).toList();
        _chamados = chamados;
      });
    } catch (_) {}
  }

  void _aviso(String t, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: erro ? const Color(0xFFE11D48) : const Color(0xFF059669),
    ));
  }

  String? _nulo(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _guardar() async {
    if (_patrimonio.text.trim().isEmpty) {
      _aviso('Indique o número de patrimônio.', erro: true);
      return;
    }
    setState(() => _aGuardar = true);
    try {
      String? data;
      if (_garantia != null) {
        data = '${_garantia!.year.toString().padLeft(4, '0')}-'
            '${_garantia!.month.toString().padLeft(2, '0')}-'
            '${_garantia!.day.toString().padLeft(2, '0')}';
      }
      await InventarioService.instance.salvar({
        'patrimonio': _patrimonio.text.trim(),
        'tipo': _tipo,
        'numero_serie': _nulo(_serie),
        'modelo': _nulo(_modelo),
        'id_responsavel': _responsavel,
        'setor': _nulo(_setor),
        'localizacao': _nulo(_local),
        'garantia_ate': data,
        'situacao': _situacao,
        'observacoes': _nulo(_obs),
      }, id: _original?['id']);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      final duplicado = e is PostgrestException && e.code == '23505';
      _aviso(
        duplicado
            ? 'Já existe um equipamento com este patrimônio.'
            : (e is PostgrestException ? e.message : 'Não foi possível guardar.'),
        erro: true,
      );
      if (mounted) setState(() => _aGuardar = false);
    }
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir equipamento?'),
        content: const Text('Os chamados vinculados são mantidos, mas deixam de ter equipamento.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await InventarioService.instance.excluir(_original!['id']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _aviso('Não foi possível excluir.', erro: true);
    }
  }

  Future<void> _escolherGarantia() async {
    final agora = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _garantia ?? agora,
      firstDate: DateTime(agora.year - 10),
      lastDate: DateTime(agora.year + 10),
    );
    if (d != null) setState(() => _garantia = d);
  }

  Widget _campo(String rotulo, TextEditingController c, {int linhas = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          controller: c,
          maxLines: linhas,
          decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder()),
        ),
      );

  Widget _lista(String rotulo, String valor, List<String> opcoes, ValueChanged<String> aoMudar) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String>(
          value: valor,
          decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder()),
          items: [for (final o in opcoes) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) {
            if (v != null) aoMudar(v);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final novo = _original == null;
    final recentes = _chamados
        .where((c) => (DateTime.tryParse('${c['created_at']}') ?? DateTime(2000))
            .isAfter(DateTime.now().subtract(const Duration(days: 90))))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: Text(novo ? 'Novo equipamento' : 'Equipamento', style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (!novo && _admin)
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Excluir', onPressed: _excluir),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.cBorda, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _campo('Patrimônio *', _patrimonio),
          _lista('Tipo', _tipo, InventarioService.tipos, (v) => setState(() => _tipo = v)),
          _campo('Número de série', _serie),
          _campo('Modelo', _modelo),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<String?>(
              value: _usuarios.any((u) => u['id'] == _responsavel) ? _responsavel : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Utilizador responsável', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— Sem responsável —')),
                for (final u in _usuarios)
                  DropdownMenuItem<String?>(
                    value: '${u['id']}',
                    child: Text('${u['nome']} (${u['email']})', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _responsavel = v),
            ),
          ),
          _campo('Setor', _setor),
          _campo('Localização', _local),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _escolherGarantia,
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(_garantia == null ? 'Garantia: sem data' : 'Garantia até ${_dataCurta(_garantia!.toIso8601String())}'),
                ),
              ),
              if (_garantia != null)
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _garantia = null)),
            ]),
          ),
          _lista('Situação', _situacao, InventarioService.situacoes, (v) => setState(() => _situacao = v)),
          _campo('Observações', _obs, linhas: 3),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF042C5C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _aGuardar ? null : _guardar,
              child: _aGuardar
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          if (!novo) ...[
            const SizedBox(height: 28),
            Text(
              'Histórico de problemas',
              style: TextStyle(color: context.cTexto, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${_chamados.length} ${_chamados.length == 1 ? 'chamado' : 'chamados'} no total · $recentes nos últimos 90 dias',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            if (recentes >= limiteRecorrente)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFE4E6), borderRadius: BorderRadius.circular(12)),
                child: const Row(children: [
                  Icon(Icons.local_fire_department, color: Color(0xFFE11D48)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Defeitos recorrentes: avalie reparar ou substituir este equipamento.',
                      style: TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            for (final c in _chamados)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${codigoTicket(c['id'])} · ${c['titulo']}'),
                subtitle: Text('${c['status']} · ${tempoDecorrido(c['created_at'] as String?)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final nav = Navigator.of(context);
                  final t = await TicketService.instance.chamadoPorId(c['id']);
                  if (t == null) {
                    _aviso('Este chamado pertence a outro técnico.');
                    return;
                  }
                  nav.pushNamed('/ticket_details', arguments: t);
                },
              ),
          ],
        ],
      ),
    );
  }
}
