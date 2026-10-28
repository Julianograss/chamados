import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/admin_service.dart';
import '../tema.dart';

/// Configuração do SLA (administrador): prazos por prioridade, prazo de
/// primeira resposta, horário comercial, dias úteis e feriados.
class telaConfigSla extends StatefulWidget {
  const telaConfigSla({super.key});

  @override
  State<telaConfigSla> createState() => _telaConfigSlaState();
}

class _telaConfigSlaState extends State<telaConfigSla> {
  bool _carregando = true;
  bool _erro = false;
  bool _aGuardar = false;

  bool _comercial = false;
  TimeOfDay _inicio = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _fim = const TimeOfDay(hour: 18, minute: 0);
  Set<int> _dias = {1, 2, 3, 4, 5};
  final _fuso = TextEditingController();
  final _resAlta = TextEditingController();
  final _resMedia = TextEditingController();
  final _resBaixa = TextEditingController();
  final _prAlta = TextEditingController();
  final _prMedia = TextEditingController();
  final _prBaixa = TextEditingController();
  List<Map<String, dynamic>> _feriados = const [];

  static const _nomesDias = {1: 'Seg', 2: 'Ter', 3: 'Qua', 4: 'Qui', 5: 'Sex', 6: 'Sáb', 7: 'Dom'};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_fuso, _resAlta, _resMedia, _resBaixa, _prAlta, _prMedia, _prBaixa]) {
      c.dispose();
    }
    super.dispose();
  }

  static TimeOfDay _hora(String? s) {
    final p = (s ?? '08:00').split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 8, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  static String _fmtHora(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  static String _num(dynamic v) {
    final n = (v as num?) ?? 0;
    return n == n.roundToDouble() ? '${n.round()}' : '$n';
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = false;
    });
    try {
      final r = await Future.wait([
        AdminService.instance.lerConfigSla(),
        AdminService.instance.listarFeriados(),
      ]);
      final c = r[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _comercial = c['usar_horario_comercial'] == true;
        _inicio = _hora(c['hora_inicio'] as String?);
        _fim = _hora(c['hora_fim'] as String?);
        _dias = {for (final d in (c['dias_uteis'] as List? ?? const [])) (d as num).toInt()};
        _fuso.text = '${c['fuso']}';
        _resAlta.text = _num(c['res_alta']);
        _resMedia.text = _num(c['res_media']);
        _resBaixa.text = _num(c['res_baixa']);
        _prAlta.text = _num(c['pr_alta']);
        _prMedia.text = _num(c['pr_media']);
        _prBaixa.text = _num(c['pr_baixa']);
        _feriados = r[1] as List<Map<String, dynamic>>;
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

  void _aviso(String t, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: erro ? const Color(0xFFE11D48) : const Color(0xFF059669),
    ));
  }

  Future<void> _guardar() async {
    num? lerNum(TextEditingController c) => num.tryParse(c.text.trim().replaceAll(',', '.'));
    final valores = [_resAlta, _resMedia, _resBaixa, _prAlta, _prMedia, _prBaixa].map(lerNum).toList();
    if (valores.any((v) => v == null || v <= 0)) {
      _aviso('Os prazos têm de ser números maiores que zero.', erro: true);
      return;
    }
    if (_dias.isEmpty) {
      _aviso('Escolha pelo menos um dia útil.', erro: true);
      return;
    }
    if (_fim.hour * 60 + _fim.minute <= _inicio.hour * 60 + _inicio.minute) {
      _aviso('A hora de fim tem de ser depois da hora de início.', erro: true);
      return;
    }
    setState(() => _aGuardar = true);
    try {
      await AdminService.instance.guardarConfigSla({
        'usar_horario_comercial': _comercial,
        'hora_inicio': _fmtHora(_inicio),
        'hora_fim': _fmtHora(_fim),
        'dias_uteis': (_dias.toList()..sort()),
        'fuso': _fuso.text.trim().isEmpty ? 'America/Sao_Paulo' : _fuso.text.trim(),
        'res_alta': valores[0]!.round(),
        'res_media': valores[1]!.round(),
        'res_baixa': valores[2]!.round(),
        'pr_alta': valores[3],
        'pr_media': valores[4],
        'pr_baixa': valores[5],
      });
      _aviso('Configuração guardada. Vale para os próximos cálculos de prazo.');
    } catch (e) {
      _aviso(e is PostgrestException ? e.message : 'Não foi possível guardar.', erro: true);
    } finally {
      if (mounted) setState(() => _aGuardar = false);
    }
  }

  Future<void> _escolherHora(bool inicio) async {
    final t = await showTimePicker(context: context, initialTime: inicio ? _inicio : _fim);
    if (t != null) setState(() => inicio ? _inicio = t : _fim = t);
  }

  Future<void> _adicionarFeriado() async {
    final agora = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: agora,
      firstDate: DateTime(agora.year - 1),
      lastDate: DateTime(agora.year + 3),
    );
    if (data == null || !mounted) return;
    final nome = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogoDescricao(),
    );
    if (nome == null) return;
    try {
      await AdminService.instance.adicionarFeriado(data, nome);
      _feriados = await AdminService.instance.listarFeriados();
      if (mounted) setState(() {});
    } catch (_) {
      _aviso('Não foi possível adicionar o feriado.', erro: true);
    }
  }

  Future<void> _removerFeriado(String data) async {
    try {
      await AdminService.instance.removerFeriado(data);
      _feriados = await AdminService.instance.listarFeriados();
      if (mounted) setState(() {});
    } catch (_) {
      _aviso('Não foi possível remover o feriado.', erro: true);
    }
  }

  Widget _campo(String rotulo, TextEditingController c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder()),
          ),
        ),
      );

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(
          t,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuração do SLA', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.cBorda, height: 1),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro
              ? Center(
                  child: TextButton(onPressed: _carregar, child: const Text('Erro ao carregar. Tentar novamente')),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _titulo('PRAZO DE RESOLUÇÃO (HORAS)'),
                    Row(children: [_campo('Alta', _resAlta), _campo('Média', _resMedia), _campo('Baixa', _resBaixa)]),
                    _titulo('PRAZO DE PRIMEIRA RESPOSTA (HORAS)'),
                    Row(children: [_campo('Alta', _prAlta), _campo('Média', _prMedia), _campo('Baixa', _prBaixa)]),
                    _titulo('HORÁRIO COMERCIAL'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _comercial,
                      onChanged: (v) => setState(() => _comercial = v),
                      title: const Text('Contar só horas úteis'),
                      subtitle: const Text(
                        'Desligado: horas corridas. Ligado: só conta dentro do horário, nos dias úteis e fora de feriados.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    if (_comercial) ...[
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _escolherHora(true),
                            child: Text('Início: ${_inicio.format(context)}'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _escolherHora(false),
                            child: Text('Fim: ${_fim.format(context)}'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, children: [
                        for (final e in _nomesDias.entries)
                          FilterChip(
                            label: Text(e.value),
                            selected: _dias.contains(e.key),
                            onSelected: (v) => setState(() => v ? _dias.add(e.key) : _dias.remove(e.key)),
                          ),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fuso,
                        decoration: const InputDecoration(
                          labelText: 'Fuso horário (ex.: America/Sao_Paulo, Europe/Lisbon)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      _titulo('FERIADOS'),
                      for (final f in _feriados)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_busy_outlined),
                          title: Text('${f['data']}'),
                          subtitle: Text('${f['descricao']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removerFeriado('${f['data']}'),
                          ),
                        ),
                      TextButton.icon(
                        onPressed: _adicionarFeriado,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar feriado'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF042C5C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _aGuardar ? null : _guardar,
                        child: _aGuardar
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'As alterações aplicam-se aos prazos calculados a partir de agora; '
                      'os prazos já calculados não são recalculados.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
    );
  }
}

class _DialogoDescricao extends StatefulWidget {
  const _DialogoDescricao();

  @override
  State<_DialogoDescricao> createState() => _DialogoDescricaoState();
}

class _DialogoDescricaoState extends State<_DialogoDescricao> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nome do feriado'),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
        onSubmitted: (_) => Navigator.of(context).pop(_c.text),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.of(context).pop(_c.text), child: const Text('Adicionar')),
      ],
    );
  }
}
