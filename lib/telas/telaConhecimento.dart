import 'package:flutter/material.dart';

import '../servicos/auth_service.dart';
import '../servicos/conhecimento_service.dart';
import '../tema.dart';

/// Base de conhecimento: tutoriais, perguntas frequentes e procedimentos.
class telaConhecimento extends StatefulWidget {
  const telaConhecimento({super.key});

  @override
  State<telaConhecimento> createState() => _telaConhecimentoState();
}

class _telaConhecimentoState extends State<telaConhecimento> {
  List<Map<String, dynamic>> _artigos = const [];
  bool _carregando = true;
  bool _erro = false;
  bool _staff = false;
  String _busca = '';
  String? _categoria;

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
      final perfil = await AuthService.instance.perfilAtual();
      final role = perfil?['role'];
      final artigos = await ConhecimentoService.instance.listar();
      if (!mounted) return;
      setState(() {
        _staff = role == 'tecnico' || role == 'admin';
        _artigos = artigos;
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

  Future<void> _abrir(Map<String, dynamic> artigo) async {
    final r = await Navigator.of(context).pushNamed('/artigo', arguments: {'artigo': artigo});
    if (r == true) _carregar();
  }

  Future<void> _novo() async {
    final r = await Navigator.of(context).pushNamed('/editar_artigo');
    if (r == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    var lista = ConhecimentoService.pesquisar(_artigos, _busca);
    if (_categoria != null) lista = lista.where((a) => a['categoria'] == _categoria).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Base de conhecimento', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.cBorda, height: 1),
        ),
      ),
      floatingActionButton: _staff
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
              onPressed: _novo,
              icon: const Icon(Icons.add),
              label: const Text('Novo artigo'),
            )
          : null,
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
                          hintText: 'Pesquisar tutoriais e perguntas frequentes...',
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
                        for (final c in ConhecimentoService.categorias)
                          ChoiceChip(
                            label: Text(c),
                            selected: _categoria == c,
                            showCheckmark: false,
                            selectedColor: const Color(0xFF0066FF),
                            labelStyle: TextStyle(
                              color: _categoria == c ? Colors.white : context.cTexto,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            onSelected: (_) => setState(() => _categoria = _categoria == c ? null : c),
                          ),
                      ]),
                      const SizedBox(height: 16),
                      if (lista.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('Nenhum artigo encontrado.')),
                        ),
                      for (final a in lista)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: context.cSuperficie,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.cBorda),
                          ),
                          child: ListTile(
                            onTap: () => _abrir(a),
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFDBEAFE),
                              child: Icon(Icons.menu_book_outlined, color: Color(0xFF1D4ED8)),
                            ),
                            title: Text(
                              '${a['titulo']}',
                              style: TextStyle(color: context.cTexto, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ('${a['resumo'] ?? ''}'.isNotEmpty)
                                  Text('${a['resumo']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 6),
                                Wrap(spacing: 6, children: [
                                  _selo('${a['categoria']}', context.cBorda, context.cTexto2),
                                  if (a['publicado'] == false)
                                    _selo('Rascunho', const Color(0xFFFEF3C7), const Color(0xFFD97706)),
                                ]),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _selo(String t, Color fundo, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold)),
      );
}
