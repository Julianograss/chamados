import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/auth_service.dart';
import '../servicos/catalogo_service.dart';
import '../servicos/horas_service.dart';
import '../servicos/inventario_service.dart';
import '../servicos/ticket_service.dart';
import '../tema.dart';

BoxDecoration _caixa(BuildContext context) => BoxDecoration(
      color: context.cSuperficie,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.cBorda),
    );

Widget _titulo(BuildContext context, String t, {Widget? direita}) => Row(
      children: [
        Expanded(
          child: Text(
            t,
            style: TextStyle(color: context.cTexto, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        if (direita != null) direita,
      ],
    );

void _aviso(BuildContext context, String t, {bool erro = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(t),
    backgroundColor: erro ? const Color(0xFFE11D48) : const Color(0xFF059669),
  ));
}

String _msg(Object e) => e is PostgrestException ? e.message : 'Não foi possível concluir. Tente novamente.';

// =====================================================================
// Serviço pedido e respostas do formulário
// =====================================================================

class CartaoServico extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final bool staff;
  const CartaoServico({super.key, required this.ticket, required this.staff});

  @override
  Widget build(BuildContext context) {
    final respostas = (ticket['campos_servico'] is List)
        ? [for (final r in ticket['campos_servico'] as List) if (r is Map) Map<String, dynamic>.from(r)]
        : <Map<String, dynamic>>[];
    final idServico = ticket['id_servico'];
    final sugerida = ticket['prioridade_sugerida'] as String?;
    final mostrarSugestao = staff && sugerida != null && ticket['prioridade'] == null;
    if (idServico == null && respostas.isEmpty && !mostrarSugestao) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: _caixa(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: idServico == null ? null : CatalogoService.instance.listar(incluirInativos: true),
            builder: (context, snap) {
              final nome = snap.data
                  ?.where((s) => '${s['id']}' == '$idServico')
                  .map((s) => '${s['nome']}')
                  .firstOrNull;
              return _titulo(context, nome == null ? 'Pedido' : 'Serviço: $nome');
            },
          ),
          if (mostrarSugestao) ...[
            const SizedBox(height: 8),
            Text(
              'Prioridade sugerida pelo serviço: $sugerida',
              style: const TextStyle(color: Color(0xFFD97706), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
          for (final r in respostas) ...[
            const SizedBox(height: 10),
            Text('${r['rotulo']}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('${r['valor']}', style: TextStyle(color: context.cTexto2, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// Equipamento vinculado ao chamado
// =====================================================================

class CartaoEquipamento extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final bool staff;
  final bool podeEditar;
  const CartaoEquipamento({super.key, required this.ticket, required this.staff, required this.podeEditar});

  @override
  State<CartaoEquipamento> createState() => _CartaoEquipamentoState();
}

class _CartaoEquipamentoState extends State<CartaoEquipamento> {
  Map<String, dynamic>? _asset;
  bool _carregando = false;
  bool _aAgir = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant CartaoEquipamento antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.ticket['id_asset'] != widget.ticket['id_asset']) _carregar();
  }

  Future<void> _carregar() async {
    final id = widget.ticket['id_asset'];
    if (id == null) {
      setState(() => _asset = null);
      return;
    }
    setState(() => _carregando = true);
    try {
      final a = await InventarioService.instance.porId(id);
      if (mounted) setState(() => _asset = a);
    } catch (_) {
      // sem permissão para ver o equipamento: mostra só o aviso genérico
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _vincular(dynamic idAsset) async {
    if (_aAgir) return;
    setState(() => _aAgir = true);
    try {
      await InventarioService.instance.vincularAoChamado(widget.ticket['id'], idAsset);
      if (mounted) _aviso(context, idAsset == null ? 'Equipamento desvinculado.' : 'Equipamento vinculado.');
    } catch (e) {
      if (mounted) _aviso(context, _msg(e), erro: true);
    } finally {
      if (mounted) setState(() => _aAgir = false);
    }
  }

  Future<void> _escolher() async {
    List<Map<String, dynamic>> todos;
    try {
      todos = await InventarioService.instance.listar();
    } catch (_) {
      if (mounted) _aviso(context, 'Não foi possível carregar o inventário.', erro: true);
      return;
    }
    if (!mounted) return;
    final cliente = '${widget.ticket['id_cliente']}';
    todos.sort((a, b) {
      final da = '${a['id_responsavel']}' == cliente ? 0 : 1;
      final db = '${b['id_responsavel']}' == cliente ? 0 : 1;
      return da != db ? da.compareTo(db) : '${a['patrimonio']}'.compareTo('${b['patrimonio']}');
    });
    final escolhido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cSuperficie,
      builder: (_) => _EscolherAsset(assets: todos, cliente: cliente),
    );
    if (escolhido != null) await _vincular(escolhido['id']);
  }

  @override
  Widget build(BuildContext context) {
    final a = _asset;
    final temId = widget.ticket['id_asset'] != null;
    if (!temId && !widget.podeEditar) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: _caixa(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titulo(context, 'Equipamento'),
          const SizedBox(height: 8),
          if (_carregando)
            const LinearProgressIndicator()
          else if (!temId)
            const Text('Nenhum equipamento vinculado.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13))
          else if (a == null)
            const Text('Equipamento vinculado.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13))
          else ...[
            Text(
              '${a['patrimonio']}${(a['modelo'] ?? '').toString().isEmpty ? '' : ' · ${a['modelo']}'}',
              style: TextStyle(color: context.cTexto, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              [
                '${a['tipo']}',
                if ((a['setor'] ?? '').toString().isNotEmpty) '${a['setor']}',
                if ((a['localizacao'] ?? '').toString().isNotEmpty) '${a['localizacao']}',
                '${a['situacao']}',
              ].join(' · '),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ],
          if ((widget.staff && temId && a != null) || widget.podeEditar) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (widget.staff && temId && a != null)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/asset', arguments: a),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Ficha e histórico'),
                ),
              if (widget.podeEditar)
                TextButton.icon(
                  onPressed: _aAgir ? null : _escolher,
                  icon: const Icon(Icons.link, size: 18),
                  label: Text(temId ? 'Trocar' : 'Vincular equipamento'),
                ),
              if (widget.podeEditar && temId)
                TextButton.icon(
                  onPressed: _aAgir ? null : () => _vincular(null),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Remover'),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _EscolherAsset extends StatefulWidget {
  final List<Map<String, dynamic>> assets;
  final String cliente;
  const _EscolherAsset({required this.assets, required this.cliente});

  @override
  State<_EscolherAsset> createState() => _EscolherAssetState();
}

class _EscolherAssetState extends State<_EscolherAsset> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final termo = _busca.trim().toLowerCase();
    final lista = widget.assets.where((a) {
      if (termo.isEmpty) return true;
      return '${a['patrimonio']} ${a['modelo'] ?? ''} ${a['numero_serie'] ?? ''} ${a['setor'] ?? ''}'
          .toLowerCase()
          .contains(termo);
    }).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _busca = v),
                  decoration: const InputDecoration(
                    hintText: 'Pesquisar patrimônio, modelo, série...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Flexible(
                child: lista.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('Nenhum equipamento encontrado.'))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: lista.length,
                        itemBuilder: (context, i) {
                          final a = lista[i];
                          final doCliente = '${a['id_responsavel']}' == widget.cliente;
                          return ListTile(
                            title: Text('${a['patrimonio']}${(a['modelo'] ?? '').toString().isEmpty ? '' : ' · ${a['modelo']}'}'),
                            subtitle: Text('${a['tipo']} · ${a['situacao']}${doCliente ? ' · do cliente' : ''}'),
                            onTap: () => Navigator.of(context).pop(a),
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
}

// =====================================================================
// Apontamento de horas (técnicos)
// =====================================================================

class CartaoHoras extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final bool podeRegistrar;
  const CartaoHoras({super.key, required this.ticket, required this.podeRegistrar});

  @override
  State<CartaoHoras> createState() => _CartaoHorasState();
}

class _CartaoHorasState extends State<CartaoHoras> {
  List<Map<String, dynamic>> _registos = const [];
  Map<String, String> _nomes = const {};
  bool _carregando = true;
  bool _erro = false;
  bool _admin = false;

  String? get _meuId => AuthService.instance.utilizadorAtual?.id;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final perfil = await AuthService.instance.perfilAtual();
      final lista = await HorasService.instance.listar(widget.ticket['id']);
      final ids = {for (final r in lista) '${r['id_tecnico']}'}.toList();
      final nomes = ids.isEmpty ? <String, String>{} : await TicketService.instance.nomesDe(ids);
      if (!mounted) return;
      setState(() {
        _admin = perfil?['role'] == 'admin';
        _registos = lista;
        _nomes = nomes;
        _carregando = false;
        _erro = false;
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

  int get _total => _registos.fold<int>(0, (a, r) => a + ((r['minutos'] as num?)?.toInt() ?? 0));

  Future<void> _registar() async {
    final r = await showDialog<_NovoRegisto>(context: context, builder: (_) => const _DialogoHoras());
    if (r == null || !mounted) return;
    try {
      await HorasService.instance.registrar(widget.ticket['id'], r.minutos, r.descricao, r.data);
      _aviso(context, 'Horas registadas.');
      await _carregar();
    } catch (e) {
      if (mounted) _aviso(context, _msg(e), erro: true);
    }
  }

  Future<void> _estimar() async {
    final atual = (widget.ticket['minutos_estimados'] as num?)?.toInt();
    final r = await showDialog<_Estimativa>(context: context, builder: (_) => _DialogoEstimativa(atual: atual));
    if (r == null || !mounted) return;
    try {
      await HorasService.instance.definirEstimativa(widget.ticket['id'], r.minutos);
      if (mounted) _aviso(context, r.minutos == null ? 'Estimativa removida.' : 'Estimativa guardada.');
    } catch (e) {
      if (mounted) _aviso(context, _msg(e), erro: true);
    }
  }

  Future<void> _apagar(Map<String, dynamic> r) async {
    try {
      await HorasService.instance.excluir(r['id']);
      await _carregar();
    } catch (e) {
      if (mounted) _aviso(context, _msg(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimado = (widget.ticket['minutos_estimados'] as num?)?.toInt();
    final total = _total;
    final acima = estimado != null && total > estimado;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: _caixa(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titulo(context, 'Horas de trabalho'),
          const SizedBox(height: 8),
          if (_carregando)
            const LinearProgressIndicator()
          else if (_erro)
            const Text('Não foi possível carregar as horas.', style: TextStyle(color: Color(0xFF64748B)))
          else ...[
            Wrap(spacing: 16, runSpacing: 4, children: [
              Text('Registado: ${HorasService.formatar(total)}',
                  style: TextStyle(color: acima ? const Color(0xFFE11D48) : context.cTexto, fontWeight: FontWeight.w600)),
              Text('Estimado: ${HorasService.formatar(estimado)}', style: const TextStyle(color: Color(0xFF64748B))),
              if (estimado != null)
                Text(
                  '${(total * 100 / estimado).round()}% da estimativa',
                  style: TextStyle(color: acima ? const Color(0xFFE11D48) : const Color(0xFF64748B), fontSize: 12),
                ),
            ]),
            for (final r in _registos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${HorasService.formatar(r['minutos'] as num?)} · ${r['descricao']}'),
                subtitle: Text('${_nomes['${r['id_tecnico']}'] ?? 'Técnico'} · ${'${r['data_trabalho']}'.split('-').reversed.join('/')}'),
                trailing: ('${r['id_tecnico']}' == _meuId || _admin)
                    ? IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _apagar(r))
                    : null,
              ),
            if (_registos.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Ainda não há horas registadas.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
              ),
          ],
          if (widget.podeRegistrar) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              TextButton.icon(onPressed: _registar, icon: const Icon(Icons.add_alarm, size: 18), label: const Text('Registar horas')),
              TextButton.icon(onPressed: _estimar, icon: const Icon(Icons.timer_outlined, size: 18), label: const Text('Estimativa')),
            ]),
          ],
        ],
      ),
    );
  }
}

class _NovoRegisto {
  final int minutos;
  final String descricao;
  final DateTime data;
  const _NovoRegisto(this.minutos, this.descricao, this.data);
}

class _Estimativa {
  final int? minutos;
  const _Estimativa(this.minutos);
}

class _DialogoHoras extends StatefulWidget {
  const _DialogoHoras();

  @override
  State<_DialogoHoras> createState() => _DialogoHorasState();
}

class _DialogoHorasState extends State<_DialogoHoras> {
  final _h = TextEditingController(text: '0');
  final _m = TextEditingController(text: '30');
  final _desc = TextEditingController();
  DateTime _data = DateTime.now();
  String? _erro;

  @override
  void dispose() {
    _h.dispose();
    _m.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _guardar() {
    final minutos = (int.tryParse(_h.text.trim()) ?? 0) * 60 + (int.tryParse(_m.text.trim()) ?? 0);
    if (minutos < 1 || minutos > 1440) {
      setState(() => _erro = 'Indique entre 1 minuto e 24 horas.');
      return;
    }
    if (_desc.text.trim().isEmpty) {
      setState(() => _erro = 'Descreva as atividades realizadas.');
      return;
    }
    Navigator.of(context).pop(_NovoRegisto(minutos, _desc.text.trim(), _data));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registar horas'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _h,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Horas'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _m,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Minutos'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Atividades realizadas'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.event, size: 18),
                label: Text('Data: ${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _data,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _data = d);
                },
              ),
            ),
            if (_erro != null)
              Text(_erro!, style: const TextStyle(color: Color(0xFFE11D48), fontSize: 13)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        TextButton(onPressed: _guardar, child: const Text('Registar')),
      ],
    );
  }
}

class _DialogoEstimativa extends StatefulWidget {
  final int? atual;
  const _DialogoEstimativa({required this.atual});

  @override
  State<_DialogoEstimativa> createState() => _DialogoEstimativaState();
}

class _DialogoEstimativaState extends State<_DialogoEstimativa> {
  late final TextEditingController _h = TextEditingController(text: '${(widget.atual ?? 60) ~/ 60}');
  late final TextEditingController _m = TextEditingController(text: '${(widget.atual ?? 60) % 60}');
  String? _erro;

  @override
  void dispose() {
    _h.dispose();
    _m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Estimativa de esforço'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: TextField(controller: _h, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Horas')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(controller: _m, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutos')),
            ),
          ]),
          if (_erro != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_erro!, style: const TextStyle(color: Color(0xFFE11D48), fontSize: 13)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        if (widget.atual != null)
          TextButton(onPressed: () => Navigator.of(context).pop(const _Estimativa(null)), child: const Text('Remover')),
        TextButton(
          onPressed: () {
            final min = (int.tryParse(_h.text.trim()) ?? 0) * 60 + (int.tryParse(_m.text.trim()) ?? 0);
            if (min < 1) {
              setState(() => _erro = 'Indique um tempo maior que zero.');
              return;
            }
            Navigator.of(context).pop(_Estimativa(min));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
