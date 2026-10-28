import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/catalogo_service.dart';
import '../tema.dart';

/// Gestão do catálogo de serviços de TI (administrador).
class telaServicos extends StatefulWidget {
  const telaServicos({super.key});

  @override
  State<telaServicos> createState() => _telaServicosState();
}

class _telaServicosState extends State<telaServicos> {
  List<Map<String, dynamic>> _servicos = const [];
  bool _carregando = true;
  bool _erro = false;

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
      final s = await CatalogoService.instance.listar(incluirInativos: true);
      if (!mounted) return;
      setState(() {
        _servicos = s;
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

  Future<void> _abrir([Map<String, dynamic>? s]) async {
    final r = await Navigator.of(context).pushNamed('/editar_servico', arguments: s);
    if (r == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo de serviços', style: TextStyle(fontWeight: FontWeight.bold)),
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
        label: const Text('Novo serviço'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro
              ? Center(child: TextButton(onPressed: _carregar, child: const Text('Erro ao carregar. Tentar novamente')))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
                  children: [
                    for (final s in _servicos)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: context.cSuperficie,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.cBorda),
                        ),
                        child: ListTile(
                          onTap: () => _abrir(s),
                          title: Text(
                            '${s['nome']}',
                            style: TextStyle(
                              color: s['ativo'] == false ? const Color(0xFF94A3B8) : context.cTexto,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text([
                            if (s['categoria_padrao'] != null) '${s['categoria_padrao']}',
                            if (s['prioridade_sugerida'] != null) 'Prioridade sugerida: ${s['prioridade_sugerida']}',
                            '${CatalogoService.camposDe(s).length} campos',
                            if (s['ativo'] == false) 'Inativo',
                          ].join(' · ')),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _CampoEdit {
  final TextEditingController rotulo;
  final TextEditingController opcoes;
  String tipo;
  bool obrigatorio;
  _CampoEdit({String rotulo = '', String opcoes = '', this.tipo = 'texto', this.obrigatorio = false})
      : rotulo = TextEditingController(text: rotulo),
        opcoes = TextEditingController(text: opcoes);

  void dispose() {
    rotulo.dispose();
    opcoes.dispose();
  }
}

/// Criar/editar um serviço do catálogo, incluindo os seus campos.
class telaEditarServico extends StatefulWidget {
  const telaEditarServico({super.key});

  @override
  State<telaEditarServico> createState() => _telaEditarServicoState();
}

class _telaEditarServicoState extends State<telaEditarServico> {
  final _nome = TextEditingController();
  final _descricao = TextEditingController();
  final _instrucoes = TextEditingController();
  final _ordem = TextEditingController(text: '0');
  String? _categoria;
  String? _prioridade;
  bool _exigeEquipamento = false;
  bool _ativo = true;
  final List<_CampoEdit> _campos = [];
  Map<String, dynamic>? _original;
  bool _iniciado = false;
  bool _aGuardar = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final s = Map<String, dynamic>.from(args);
      _original = s;
      _nome.text = '${s['nome']}';
      _descricao.text = '${s['descricao'] ?? ''}';
      _instrucoes.text = '${s['instrucoes'] ?? ''}';
      _ordem.text = '${s['ordem'] ?? 0}';
      _categoria = s['categoria_padrao'] as String?;
      _prioridade = s['prioridade_sugerida'] as String?;
      _exigeEquipamento = s['exige_equipamento'] == true;
      _ativo = s['ativo'] != false;
      for (final c in CatalogoService.camposDe(s)) {
        _campos.add(_CampoEdit(
          rotulo: '${c['rotulo']}',
          opcoes: ((c['opcoes'] as List?) ?? const []).join(', '),
          tipo: '${c['tipo']}',
          obrigatorio: c['obrigatorio'] == true,
        ));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_nome, _descricao, _instrucoes, _ordem]) {
      c.dispose();
    }
    for (final c in _campos) {
      c.dispose();
    }
    super.dispose();
  }

  void _aviso(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: const Color(0xFFE11D48)));
  }

  Future<void> _guardar() async {
    if (_nome.text.trim().isEmpty) {
      _aviso('Indique o nome do serviço.');
      return;
    }
    final campos = <Map<String, dynamic>>[];
    for (var i = 0; i < _campos.length; i++) {
      final c = _campos[i];
      final rotulo = c.rotulo.text.trim();
      if (rotulo.isEmpty) {
        _aviso('Todos os campos precisam de um nome.');
        return;
      }
      final opcoes = [
        for (final o in c.opcoes.text.split(','))
          if (o.trim().isNotEmpty) o.trim(),
      ];
      if (c.tipo == 'selecao' && opcoes.length < 2) {
        _aviso('O campo "$rotulo" precisa de pelo menos 2 opções.');
        return;
      }
      campos.add({
        'chave': 'campo_${i + 1}',
        'rotulo': rotulo,
        'tipo': c.tipo,
        'obrigatorio': c.obrigatorio,
        if (c.tipo == 'selecao') 'opcoes': opcoes,
      });
    }
    setState(() => _aGuardar = true);
    try {
      await CatalogoService.instance.salvar({
        'nome': _nome.text.trim(),
        'descricao': _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
        'instrucoes': _instrucoes.text.trim().isEmpty ? null : _instrucoes.text.trim(),
        'categoria_padrao': _categoria,
        'prioridade_sugerida': _prioridade,
        'exige_equipamento': _exigeEquipamento,
        'ativo': _ativo,
        'ordem': int.tryParse(_ordem.text.trim()) ?? 0,
        'campos': campos,
      }, id: _original?['id']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _aviso(e is PostgrestException && e.code == '23505'
          ? 'Já existe um serviço com este nome.'
          : (e is PostgrestException ? e.message : 'Não foi possível guardar.'));
      if (mounted) setState(() => _aGuardar = false);
    }
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir serviço?'),
        content: const Text('Os chamados antigos são mantidos. Prefere desativar para o esconder?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CatalogoService.instance.excluir(_original!['id']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _aviso('Não foi possível excluir.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_original == null ? 'Novo serviço' : 'Editar serviço', style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_original != null) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Excluir', onPressed: _excluir),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.cBorda, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome *', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição curta', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(
            controller: _instrucoes,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Instruções para o cliente',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _categoria,
            decoration: const InputDecoration(labelText: 'Categoria padrão', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— Nenhuma —')),
              for (final c in CatalogoService.categorias) DropdownMenuItem<String?>(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _categoria = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _prioridade,
            decoration: const InputDecoration(labelText: 'Prioridade sugerida', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— Nenhuma —')),
              for (final p in CatalogoService.prioridades) DropdownMenuItem<String?>(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() => _prioridade = v),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _exigeEquipamento,
            onChanged: (v) => setState(() => _exigeEquipamento = v),
            title: const Text('Exige indicar um equipamento'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _ativo,
            onChanged: (v) => setState(() => _ativo = v),
            title: const Text('Ativo (visível para os clientes)'),
          ),
          TextField(
            controller: _ordem,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Ordem na lista', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          Text('Campos do formulário', style: TextStyle(color: context.cTexto, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (var i = 0; i < _campos.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cSuperficie,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cBorda),
              ),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _campos[i].rotulo,
                      decoration: const InputDecoration(labelText: 'Nome do campo'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _campos.removeAt(i).dispose()),
                  ),
                ]),
                DropdownButtonFormField<String>(
                  value: _campos[i].tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [
                    for (final e in CatalogoService.tiposDeCampo.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _campos[i].tipo = v ?? 'texto'),
                ),
                if (_campos[i].tipo == 'selecao')
                  TextField(
                    controller: _campos[i].opcoes,
                    decoration: const InputDecoration(labelText: 'Opções (separadas por vírgula)'),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _campos[i].obrigatorio,
                  onChanged: (v) => setState(() => _campos[i].obrigatorio = v),
                  title: const Text('Obrigatório'),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: () => setState(() => _campos.add(_CampoEdit())),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar campo'),
          ),
          const SizedBox(height: 16),
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
        ],
      ),
    );
  }
}
