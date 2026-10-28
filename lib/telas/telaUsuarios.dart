import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/admin_service.dart';
import '../servicos/auth_service.dart';
import '../tema.dart';

/// Painel administrativo de utilizadores: pesquisar, filtrar por função,
/// promover a técnico/admin, ativar/desativar contas e convidar técnicos.
class telaUsuarios extends StatefulWidget {
  const telaUsuarios({super.key});

  @override
  State<telaUsuarios> createState() => _telaUsuariosState();
}

class _telaUsuariosState extends State<telaUsuarios> {
  List<Map<String, dynamic>> _usuarios = const [];
  List<Map<String, dynamic>> _convites = const [];
  bool _carregando = true;
  bool _erro = false;
  bool _aAgir = false;
  String _busca = '';
  String? _filtroRole; // null = todas as funções
  String _filtroEstado = 'todas'; // todas | ativas | desativadas

  String? get _meuId => AuthService.instance.utilizadorAtual?.id;

  static const _roles = {'cliente': 'Cliente', 'tecnico': 'Técnico', 'admin': 'Administrador'};

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
        AdminService.instance.listarUsuarios(),
        AdminService.instance.listarConvites(),
      ]);
      if (!mounted) return;
      setState(() {
        _usuarios = r[0];
        _convites = r[1];
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

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(texto),
        backgroundColor: erro ? const Color(0xFFE11D48) : const Color(0xFF059669),
      ));
  }

  String _msgErro(Object e) =>
      e is PostgrestException ? e.message : 'Não foi possível concluir. Tente novamente.';

  Future<void> _executar(Future<void> Function() acao, String sucesso) async {
    if (_aAgir) return;
    setState(() => _aAgir = true);
    try {
      await acao();
      _aviso(sucesso);
      await _carregar();
    } catch (e) {
      _aviso(_msgErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _aAgir = false);
    }
  }

  Future<bool> _confirmar(String titulo, String texto, String botao) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(botao)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _alterarFuncao(Map<String, dynamic> u, String novaRole) async {
    final nome = '${u['nome']}';
    final ok = await _confirmar(
      'Alterar função?',
      '$nome passará a ser ${_roles[novaRole]}.',
      'Confirmar',
    );
    if (!ok) return;
    await _executar(
      () => AdminService.instance.alterarFuncao('${u['id']}', novaRole),
      '$nome agora é ${_roles[novaRole]}.',
    );
  }

  Future<void> _alternarAtivo(Map<String, dynamic> u) async {
    final nome = '${u['nome']}';
    final ativar = u['ativo'] == false;
    final ok = await _confirmar(
      ativar ? 'Reativar conta?' : 'Desativar conta?',
      ativar
          ? '$nome voltará a poder iniciar sessão e usar o sistema.'
          : '$nome deixará de conseguir usar o sistema. Os chamados dessa pessoa são mantidos.',
      ativar ? 'Reativar' : 'Desativar',
    );
    if (!ok) return;
    await _executar(
      () => AdminService.instance.definirAtivo('${u['id']}', ativar),
      ativar ? 'Conta reativada.' : 'Conta desativada.',
    );
  }

  Future<void> _convidar() async {
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _DialogoConvite(),
    );
    if (r == null || !mounted) return;
    if (_aAgir) return;
    setState(() => _aAgir = true);
    try {
      final resultado = await AdminService.instance.convidar(r.$1, r.$2);
      _aviso(resultado == 'promovido'
          ? '${r.$1} agora é ${_roles[r.$2]}.'
          : 'Convite registado. Quando ${r.$1} criar conta e confirmar o e-mail, '
              'receberá a função de ${_roles[r.$2]} automaticamente.');
      await _carregar();
    } catch (e) {
      _aviso(_msgErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _aAgir = false);
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    final termo = _busca.trim().toLowerCase();
    return _usuarios.where((u) {
      if (_filtroRole != null && u['role'] != _filtroRole) return false;
      final ativo = u['ativo'] != false;
      if (_filtroEstado == 'ativas' && !ativo) return false;
      if (_filtroEstado == 'desativadas' && ativo) return false;
      if (termo.isEmpty) return true;
      return '${u['nome']}'.toLowerCase().contains(termo) ||
          '${u['email']}'.toLowerCase().contains(termo);
    }).toList();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilizadores', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Convidar técnico',
            onPressed: _aAgir ? null : _convidar,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.cBorda, height: 1),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Não foi possível carregar os utilizadores.'),
                      TextButton(onPressed: _carregar, child: const Text('Tentar novamente')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      TextField(
                        onChanged: (v) => setState(() => _busca = v),
                        decoration: InputDecoration(
                          hintText: 'Pesquisar por nome ou e-mail...',
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
                        _chip('Todas', _filtroRole == null, () => setState(() => _filtroRole = null)),
                        for (final e in _roles.entries)
                          _chip(
                            e.value == 'Administrador' ? 'Admins' : '${e.value}s',
                            _filtroRole == e.key,
                            () => setState(() => _filtroRole = _filtroRole == e.key ? null : e.key),
                          ),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _chip('Qualquer estado', _filtroEstado == 'todas',
                            () => setState(() => _filtroEstado = 'todas')),
                        _chip('Ativas', _filtroEstado == 'ativas',
                            () => setState(() => _filtroEstado = 'ativas')),
                        _chip('Desativadas', _filtroEstado == 'desativadas',
                            () => setState(() => _filtroEstado = 'desativadas')),
                      ]),
                      if (_convites.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'CONVITES PENDENTES',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final c in _convites)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: _caixa(),
                            child: ListTile(
                              leading: const Icon(Icons.mark_email_unread_outlined),
                              title: Text('${c['email']}'),
                              subtitle: Text('Será ${_roles[c['role']] ?? c['role']}'),
                              trailing: IconButton(
                                tooltip: 'Cancelar convite',
                                icon: const Icon(Icons.close),
                                onPressed: _aAgir
                                    ? null
                                    : () => _executar(
                                          () => AdminService.instance.cancelarConvite('${c['email']}'),
                                          'Convite cancelado.',
                                        ),
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        '${lista.length} ${lista.length == 1 ? 'utilizador' : 'utilizadores'}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (lista.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('Nenhum utilizador encontrado.')),
                        ),
                      for (final u in lista) _tile(u),
                    ],
                  ),
                ),
    );
  }

  BoxDecoration _caixa() => BoxDecoration(
        color: context.cSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorda),
      );

  Widget _tile(Map<String, dynamic> u) {
    final eu = '${u['id']}' == _meuId;
    final ativo = u['ativo'] != false;
    final role = '${u['role']}';
    final nome = '${u['nome']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _caixa(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: ativo ? const Color(0xFFDBEAFE) : context.cFundoSuave,
          child: Text(
            nome.isEmpty ? '?' : nome[0].toUpperCase(),
            style: TextStyle(
              color: ativo ? const Color(0xFF1D4ED8) : const Color(0xFF94A3B8),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          eu ? '$nome (você)' : nome,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: ativo ? context.cTexto : const Color(0xFF94A3B8),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${u['email']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _selo(_roles[role] ?? role, role == 'cliente' ? context.cBorda : const Color(0xFFE0E7FF),
                  role == 'cliente' ? context.cTexto2 : const Color(0xFF3730A3)),
              if (!ativo) _selo('Desativada', const Color(0xFFFFE4E6), const Color(0xFFE11D48)),
            ]),
          ],
        ),
        isThreeLine: true,
        trailing: eu
            ? null
            : PopupMenuButton<String>(
                enabled: !_aAgir,
                tooltip: 'Ações',
                onSelected: (v) {
                  if (v == 'ativo') {
                    _alternarAtivo(u);
                  } else {
                    _alterarFuncao(u, v);
                  }
                },
                itemBuilder: (_) => [
                  for (final e in _roles.entries)
                    if (e.key != role)
                      PopupMenuItem(value: e.key, child: Text('Tornar ${e.value.toLowerCase()}')),
                  PopupMenuItem(
                    value: 'ativo',
                    child: Text(
                      ativo ? 'Desativar conta' : 'Reativar conta',
                      style: TextStyle(color: ativo ? const Color(0xFFE11D48) : const Color(0xFF059669)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _selo(String texto, Color fundo, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(10)),
        child: Text(texto, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold)),
      );
}

/// Diálogo "Convidar técnico": e-mail + função (técnico ou administrador).
class _DialogoConvite extends StatefulWidget {
  const _DialogoConvite();

  @override
  State<_DialogoConvite> createState() => _DialogoConviteState();
}

class _DialogoConviteState extends State<_DialogoConvite> {
  final _email = TextEditingController();
  String _role = 'tecnico';
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _enviar() {
    final e = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      setState(() => _erro = 'Indique um e-mail válido.');
      return;
    }
    Navigator.of(context).pop((e, _role));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Convidar técnico'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Indique o e-mail da pessoa. Se já tiver conta, passa a ter a função de imediato; '
            'caso contrário, recebe-a ao criar conta e confirmar o e-mail.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'E-mail', errorText: _erro),
            onSubmitted: (_) => _enviar(),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'tecnico', label: Text('Técnico')),
              ButtonSegment(value: 'admin', label: Text('Administrador')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        TextButton(onPressed: _enviar, child: const Text('Convidar')),
      ],
    );
  }
}
