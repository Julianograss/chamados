import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/auth_service.dart';
import '../servicos/catalogo_service.dart';
import '../servicos/conhecimento_service.dart';
import '../tema.dart';

/// Leitor de um artigo. Argumentos: {'artigo': Map, 'deChamado': bool}.
/// Quando aberto a partir da criação de um chamado, mostra "Resolveu o meu
/// problema" e devolve 'resolvido' ao fechar.
class telaArtigo extends StatefulWidget {
  const telaArtigo({super.key});

  @override
  State<telaArtigo> createState() => _telaArtigoState();
}

class _telaArtigoState extends State<telaArtigo> {
  Map<String, dynamic>? _artigo;
  bool _deChamado = false;
  bool _staff = false;
  bool _avaliou = false;
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _artigo = Map<String, dynamic>.from(args['artigo'] as Map);
      _deChamado = args['deChamado'] == true;
    }
    AuthService.instance.perfilAtual().then((p) {
      if (!mounted) return;
      final role = p?['role'];
      setState(() => _staff = role == 'tecnico' || role == 'admin');
    }).catchError((_) {});
  }

  Future<void> _avaliar(bool util) async {
    setState(() => _avaliou = true);
    try {
      await ConhecimentoService.instance.avaliar(_artigo!['id'], util);
    } catch (_) {}
  }

  Future<void> _editar() async {
    final r = await Navigator.of(context).pushNamed('/editar_artigo', arguments: _artigo);
    if (r == true && mounted) Navigator.of(context).pop(true);
  }

  /// Mini-formatação: "# título", "- item" e parágrafos.
  List<Widget> _corpo(String texto) {
    final widgets = <Widget>[];
    for (final linha in texto.split('\n')) {
      final l = linha.trimRight();
      if (l.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
      } else if (l.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            l.substring(2),
            style: TextStyle(color: context.cTexto, fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ));
      } else if (l.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: TextStyle(color: context.cTexto2)),
              Expanded(child: Text(l.substring(2), style: TextStyle(color: context.cTexto2, fontSize: 14.5, height: 1.45))),
            ],
          ),
        ));
      } else {
        widgets.add(Text(l, style: TextStyle(color: context.cTexto2, fontSize: 14.5, height: 1.5)));
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final a = _artigo;
    if (a == null) return const Scaffold(body: Center(child: Text('Artigo indisponível.')));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artigo', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_staff) IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: _editar),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.cBorda, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('${a['titulo']}', style: TextStyle(color: context.cTexto, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('${a['categoria']}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          if ('${a['resumo'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('${a['resumo']}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          ..._corpo('${a['conteudo']}'),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cSuperficie,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.cBorda),
            ),
            child: _avaliou
                ? const Text('Obrigado pelo seu feedback!', textAlign: TextAlign.center)
                : Column(
                    children: [
                      Text('Este artigo foi útil?', style: TextStyle(color: context.cTexto, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        OutlinedButton.icon(
                          onPressed: () => _avaliar(true),
                          icon: const Icon(Icons.thumb_up_outlined, size: 18),
                          label: const Text('Sim'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => _avaliar(false),
                          icon: const Icon(Icons.thumb_down_outlined, size: 18),
                          label: const Text('Não'),
                        ),
                      ]),
                    ],
                  ),
          ),
          if (_deChamado) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(context).pop('resolvido'),
                icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                label: const Text('Resolveu o meu problema', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Não resolveu — continuar a abrir o chamado'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Criar/editar um artigo (técnicos e administradores).
class telaEditarArtigo extends StatefulWidget {
  const telaEditarArtigo({super.key});

  @override
  State<telaEditarArtigo> createState() => _telaEditarArtigoState();
}

class _telaEditarArtigoState extends State<telaEditarArtigo> {
  final _titulo = TextEditingController();
  final _resumo = TextEditingController();
  final _conteudo = TextEditingController();
  final _tags = TextEditingController();
  String _categoria = 'Geral';
  int? _servico;
  bool _publicado = true;
  bool _admin = false;
  bool _aGuardar = false;
  bool _iniciado = false;
  Map<String, dynamic>? _original;
  List<Map<String, dynamic>> _servicos = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final a = Map<String, dynamic>.from(args);
      _original = a;
      _titulo.text = '${a['titulo']}';
      _resumo.text = '${a['resumo'] ?? ''}';
      _conteudo.text = '${a['conteudo']}';
      _tags.text = ((a['tags'] as List?) ?? const []).join(', ');
      _categoria = '${a['categoria']}';
      _servico = (a['id_servico'] as num?)?.toInt();
      _publicado = a['publicado'] != false;
    }
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final perfil = await AuthService.instance.perfilAtual();
      final servicos = await CatalogoService.instance.listar(incluirInativos: true);
      if (!mounted) return;
      setState(() {
        _admin = perfil?['role'] == 'admin';
        _servicos = servicos;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_titulo, _resumo, _conteudo, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  void _aviso(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: const Color(0xFFE11D48)));
  }

  Future<void> _guardar() async {
    if (_titulo.text.trim().isEmpty || _conteudo.text.trim().isEmpty) {
      _aviso('Indique o título e o conteúdo do artigo.');
      return;
    }
    setState(() => _aGuardar = true);
    try {
      await ConhecimentoService.instance.salvar({
        'titulo': _titulo.text.trim(),
        'resumo': _resumo.text.trim().isEmpty ? null : _resumo.text.trim(),
        'conteudo': _conteudo.text.trim(),
        'categoria': _categoria,
        'id_servico': _servico,
        'tags': [
          for (final t in _tags.text.split(','))
            if (t.trim().isNotEmpty) t.trim().toLowerCase(),
        ],
        'publicado': _publicado,
      }, id: _original?['id']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _aviso(e is PostgrestException ? e.message : 'Não foi possível guardar.');
      if (mounted) setState(() => _aGuardar = false);
    }
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir artigo?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ConhecimentoService.instance.excluir(_original!['id']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _aviso('Não foi possível excluir.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_original == null ? 'Novo artigo' : 'Editar artigo', style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_original != null && _admin)
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
          TextField(controller: _titulo, decoration: const InputDecoration(labelText: 'Título *', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: _resumo, decoration: const InputDecoration(labelText: 'Resumo (uma frase)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _categoria,
            decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
            items: [for (final c in ConhecimentoService.categorias) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _categoria = v ?? 'Geral'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            value: _servicos.any((s) => s['id'] == _servico) ? _servico : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sugerir ao abrir este serviço',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('— Nenhum —')),
              for (final s in _servicos)
                DropdownMenuItem<int?>(value: (s['id'] as num).toInt(), child: Text('${s['nome']}')),
            ],
            onChanged: (v) => setState(() => _servico = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: 'Palavras-chave (separadas por vírgula)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _conteudo,
            minLines: 8,
            maxLines: 20,
            decoration: const InputDecoration(
              labelText: 'Conteúdo *',
              helperText: 'Use "# Título" para secções e "- item" para listas.',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _publicado,
            onChanged: (v) => setState(() => _publicado = v),
            title: const Text('Publicado'),
            subtitle: const Text('Desligado = rascunho (só a equipa técnica vê).'),
          ),
          const SizedBox(height: 8),
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
