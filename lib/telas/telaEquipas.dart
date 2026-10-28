import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/admin_service.dart';
import '../servicos/catalogo_service.dart';
import '../servicos/equipas_service.dart';
import '../tema.dart';

/// Equipas (filas de atendimento): criar, escolher a categoria que tratam e os membros.
class telaEquipas extends StatefulWidget {
  const telaEquipas({super.key});

  @override
  State<telaEquipas> createState() => _telaEquipasState();
}

class _telaEquipasState extends State<telaEquipas> {
  List<Map<String, dynamic>> _equipas = const [];
  Map<String, List<String>> _membros = const {};
  List<Map<String, dynamic>> _tecnicos = const [];
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
      final r = await Future.wait([
        EquipasService.instance.listar(),
        EquipasService.instance.membros(),
        AdminService.instance.listarUsuarios(),
      ]);
      if (!mounted) return;
      setState(() {
        _equipas = r[0] as List<Map<String, dynamic>>;
        _membros = r[1] as Map<String, List<String>>;
        _tecnicos = (r[2] as List<Map<String, dynamic>>)
            .where((u) => (u['role'] == 'tecnico' || u['role'] == 'admin') && u['ativo'] != false)
            .toList();
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

  Future<void> _abrir([Map<String, dynamic>? equipa]) async {
    final r = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _EditarEquipa(
        equipa: equipa,
        tecnicos: _tecnicos,
        membrosAtuais: equipa == null ? const [] : (_membros['${equipa['id']}'] ?? const []),
      ),
    ));
    if (r == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipas de atendimento', style: TextStyle(fontWeight: FontWeight.bold)),
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
        label: const Text('Nova equipa'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro
              ? Center(child: TextButton(onPressed: _carregar, child: const Text('Erro ao carregar. Tentar novamente')))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
                  children: [
                    const Text(
                      'Os chamados de um serviço com categoria padrão entram na fila da equipa que trata essa categoria. '
                      'Depois, qualquer técnico pode assumir ou atribuir o chamado a alguém.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    for (final e in _equipas)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: context.cSuperficie,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.cBorda),
                        ),
                        child: ListTile(
                          onTap: () => _abrir(e),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE0E7FF),
                            child: Icon(Icons.groups_outlined, color: Color(0xFF3730A3)),
                          ),
                          title: Text('${e['nome']}', style: TextStyle(color: context.cTexto, fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            if (e['categoria'] != null) 'Categoria: ${e['categoria']}',
                            '${(_membros['${e['id']}'] ?? const []).length} membros',
                          ].join(' · ')),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _EditarEquipa extends StatefulWidget {
  final Map<String, dynamic>? equipa;
  final List<Map<String, dynamic>> tecnicos;
  final List<String> membrosAtuais;
  const _EditarEquipa({required this.equipa, required this.tecnicos, required this.membrosAtuais});

  @override
  State<_EditarEquipa> createState() => _EditarEquipaState();
}

class _EditarEquipaState extends State<_EditarEquipa> {
  late final TextEditingController _nome = TextEditingController(text: '${widget.equipa?['nome'] ?? ''}');
  late final TextEditingController _descricao = TextEditingController(text: '${widget.equipa?['descricao'] ?? ''}');
  late String? _categoria = widget.equipa?['categoria'] as String?;
  late final Set<String> _selecionados = {...widget.membrosAtuais};
  bool _aGuardar = false;

  @override
  void dispose() {
    _nome.dispose();
    _descricao.dispose();
    super.dispose();
  }

  void _aviso(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: const Color(0xFFE11D48)));
  }

  Future<void> _guardar() async {
    if (_nome.text.trim().isEmpty) {
      _aviso('Indique o nome da equipa.');
      return;
    }
    setState(() => _aGuardar = true);
    try {
      await EquipasService.instance.salvarEquipa(
        id: widget.equipa?['id'],
        nome: _nome.text.trim(),
        descricao: _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
        categoria: _categoria,
        membros: _selecionados.toList(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _aviso(e is PostgrestException && e.code == '23505'
          ? 'Já existe uma equipa com este nome.'
          : (e is PostgrestException ? e.message : 'Não foi possível guardar.'));
      if (mounted) setState(() => _aGuardar = false);
    }
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir equipa?'),
        content: const Text('Os chamados continuam, apenas deixam de ter equipa.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await EquipasService.instance.excluir(widget.equipa!['id']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _aviso('Não foi possível excluir.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.equipa == null ? 'Nova equipa' : 'Editar equipa', style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (widget.equipa != null)
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
          TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome *', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _categoria,
            decoration: const InputDecoration(labelText: 'Categoria que a equipa trata', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— Nenhuma —')),
              for (final c in CatalogoService.categorias) DropdownMenuItem<String?>(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _categoria = v),
          ),
          const SizedBox(height: 24),
          Text('Membros', style: TextStyle(color: context.cTexto, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (widget.tecnicos.isEmpty) const Text('Ainda não há técnicos ativos.'),
          for (final t in widget.tecnicos)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selecionados.contains('${t['id']}'),
              title: Text('${t['nome']}'),
              subtitle: Text('${t['email']}'),
              onChanged: (v) => setState(() => v == true ? _selecionados.add('${t['id']}') : _selecionados.remove('${t['id']}')),
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
