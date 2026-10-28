import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/admin_service.dart';
import '../servicos/csv.dart';
import '../servicos/horas_service.dart';
import '../tema.dart';

/// Painel gerencial (administrador): indicadores, gráfico por período,
/// distribuição por categoria/prioridade/técnico e exportação em CSV.
class telaGerencial extends StatefulWidget {
  const telaGerencial({super.key});

  @override
  State<telaGerencial> createState() => _telaGerencialState();
}

class _telaGerencialState extends State<telaGerencial> {
  int _dias = 30;
  String _agrupar = 'dia';
  Map<String, dynamic>? _dados;
  Map<String, dynamic>? _esforco; // horas apontadas (pode faltar se o RPC falhar)
  bool _carregando = true;
  String? _erro;
  bool _aExportar = false;

  DateTime get _de => DateTime.now().subtract(Duration(days: _dias));
  DateTime get _ate => DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final d = await AdminService.instance.relatorio(_de, _ate, _agrupar);
      Map<String, dynamic>? esforco;
      try {
        esforco = await HorasService.instance.relatorio(_de, _ate);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _dados = d;
        _esforco = esforco;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = e is PostgrestException ? e.message : 'Não foi possível carregar o relatório.';
      });
    }
  }

  // ---- formatação -------------------------------------------------------

  static num _n(dynamic v) => (v as num?) ?? 0;

  static String _minutos(dynamic v) {
    if (v == null) return '—';
    final m = (v as num).toDouble();
    if (m < 60) return '${m.round()} min';
    if (m < 1440) return '${(m / 60).toStringAsFixed(1).replaceAll('.', ',')} h';
    final d = (m / 1440).floor();
    final h = ((m - d * 1440) / 60).round();
    return '$d d $h h';
  }

  static String _pct(num ok, num total) =>
      total == 0 ? '—' : '${(ok * 100 / total).toStringAsFixed(0)}%';

  static String _rotuloPeriodo(String iso, String agrupar) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return agrupar == 'mes' ? '${p[1]}/${p[0].substring(2)}' : '${p[2]}/${p[1]}';
  }

  // ---- exportação -------------------------------------------------------

  Future<void> _exportar(String tipo) async {
    final d = _dados;
    if (d == null || _aExportar) return;
    setState(() => _aExportar = true);
    try {
      late final String csv;
      late final String nome;
      final sufixo = DateTime.now().toIso8601String().substring(0, 10);
      if (tipo == 'resumo') {
        csv = paraCsv([
          ['Relatório gerencial BlueDesk', 'Últimos $_dias dias, agrupado por $_agrupar'],
          [],
          ['Indicador', 'Valor'],
          ['Total de chamados', _n(d['total'])],
          ['Abertos', _n(d['abertos'])],
          ['Em andamento', _n(d['em_andamento'])],
          ['Pendentes', _n(d['pendentes'])],
          ['Resolvidos', _n(d['resolvidos'])],
          ['Cancelados', _n(d['cancelados'])],
          ['Atrasados', _n(d['atrasados'])],
          ['Reabertos', _n(d['reabertos'])],
          ['Tempo médio de primeira resposta', _minutos(d['tmpr_min'])],
          ['Tempo médio de resolução', _minutos(d['tmr_min'])],
          ['SLA de resolução cumprido', _pct(_n(d['sla_res_ok']), _n(d['sla_res_total']))],
          ['SLA de primeira resposta cumprido', _pct(_n(d['sla_pr_ok']), _n(d['sla_pr_total']))],
          [
            'Satisfação média (1 a 5)',
            d['csat_media'] == null ? '—' : (d['csat_media'] as num).toStringAsFixed(2)
          ],
          ['Avaliações recebidas', _n(d['csat_total'])],
          [],
          ['Por categoria', 'Chamados'],
          for (final e in (d['por_categoria'] as Map).entries) [e.key, e.value],
          [],
          ['Por prioridade', 'Chamados'],
          for (final e in (d['por_prioridade'] as Map).entries) [e.key, e.value],
          [],
          ['Técnico', 'Chamados', 'Resolvidos'],
          for (final t in (d['por_tecnico'] as List)) [t['nome'], t['total'], t['resolvidos']],
          [],
          ['Período', 'Criados', 'Resolvidos'],
          for (final s in (d['serie'] as List)) [s['periodo'], s['criados'], s['resolvidos']],
          if (_esforco != null) ...[
            [],
            ['Esforço (horas apontadas)', ''],
            ['Total de horas', HorasService.formatar(_n(_esforco!['total_min']))],
            ['Chamados com horas', _n(_esforco!['chamados'])],
            ['Média por chamado', HorasService.formatar(_esforco!['media_min'] as num?)],
            ['Estimado (chamados com estimativa)', HorasService.formatar(_n(_esforco!['estimado_min']))],
            ['Real (chamados com estimativa)', HorasService.formatar(_n(_esforco!['real_com_estimativa_min']))],
            [],
            ['Técnico', 'Minutos'],
            for (final t in (_esforco!['por_tecnico'] as List)) [t['nome'], t['minutos']],
          ],
        ]);
        nome = 'bluedesk_resumo_$sufixo.csv';
      } else {
        final r = await Future.wait([
          AdminService.instance.chamadosDoPeriodo(_de, _ate),
          AdminService.instance.listarUsuarios(),
        ]);
        final nomes = {for (final u in r[1]) '${u['id']}': '${u['nome']}'};
        csv = paraCsv([
          [
            'ID', 'Título', 'Estado', 'Categoria', 'Prioridade', 'Cliente', 'Técnico',
            'Criado em', 'Primeira resposta', 'Prazo 1ª resposta', 'Prazo resolução', 'Fechado em',
          ],
          for (final t in r[0])
            [
              t['id'], t['titulo'], t['status'], t['categoria'], t['prioridade'],
              nomes['${t['id_cliente']}'], nomes['${t['id_tecnico']}'],
              t['created_at'], t['primeira_resposta_em'], t['prazo_primeira_resposta'],
              t['prazo_resolucao'], t['data_fechamento'],
            ],
        ]);
        nome = 'bluedesk_chamados_$sufixo.csv';
      }
      await Share.shareXFiles(
        [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: nome)],
        fileNameOverrides: [nome],
        subject: nome,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível exportar.'), backgroundColor: Color(0xFFE11D48)),
        );
      }
    } finally {
      if (mounted) setState(() => _aExportar = false);
    }
  }

  // ---- widgets ----------------------------------------------------------

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

  Widget _cartao(String titulo, String valor, {Color? cor, IconData? icone}) {
    return Container(
      width: (MediaQuery.of(context).size.width - 40 - 12) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icone != null) ...[Icon(icone, size: 16, color: cor ?? const Color(0xFF64748B)), const SizedBox(width: 6)],
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(color: cor ?? context.cTexto, fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _secao(String t) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 12),
        child: Text(
          t,
          style: TextStyle(color: context.cTexto, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  Widget _barrasHorizontais(Map valores, {Color cor = const Color(0xFF0066FF)}) {
    if (valores.isEmpty) return const Text('Sem dados no período.', style: TextStyle(color: Color(0xFF64748B)));
    final maximo = valores.values.fold<num>(1, (a, b) => b > a ? b : a);
    return Column(children: [
      for (final e in valores.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            SizedBox(width: 110, child: Text('${e.key}', style: TextStyle(color: context.cTexto2, fontSize: 13))),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Stack(children: [
                  Container(height: 14, decoration: BoxDecoration(color: context.cFundoSuave, borderRadius: BorderRadius.circular(7))),
                  Container(
                    height: 14,
                    width: c.maxWidth * (e.value as num) / maximo,
                    decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(7)),
                  ),
                ]),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text('${e.value}', textAlign: TextAlign.right, style: TextStyle(color: context.cTexto, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
    ]);
  }

  Widget _grafico(List serie) {
    if (serie.isEmpty) return const Text('Sem dados no período.', style: TextStyle(color: Color(0xFF64748B)));
    final maximo = serie.fold<num>(1, (a, s) {
      final m = _n(s['criados']) > _n(s['resolvidos']) ? _n(s['criados']) : _n(s['resolvidos']);
      return m > a ? m : a;
    });
    const alturaMax = 120.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final s in serie)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _barra(_n(s['criados']), maximo, alturaMax, const Color(0xFF0066FF)),
                  const SizedBox(width: 3),
                  _barra(_n(s['resolvidos']), maximo, alturaMax, const Color(0xFF059669)),
                ]),
                const SizedBox(height: 6),
                Text(_rotuloPeriodo('${s['periodo']}', _agrupar),
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      const Row(children: [
        Icon(Icons.square, size: 12, color: Color(0xFF0066FF)),
        SizedBox(width: 4),
        Text('Criados', style: TextStyle(fontSize: 12)),
        SizedBox(width: 16),
        Icon(Icons.square, size: 12, color: Color(0xFF059669)),
        SizedBox(width: 4),
        Text('Resolvidos', style: TextStyle(fontSize: 12)),
      ]),
    ]);
  }

  Widget _barra(num valor, num maximo, double alturaMax, Color cor) {
    final h = valor == 0 ? 2.0 : (alturaMax * valor / maximo).clamp(4.0, alturaMax).toDouble();
    return Tooltip(
      message: '$valor',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$valor', style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
        Container(
          width: 12,
          height: h,
          decoration: BoxDecoration(color: cor, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
        ),
      ]),
    );
  }

  List<Widget> _secaoEsforco(Map<String, dynamic> e) {
    final estimado = _n(e['estimado_min']);
    final real = _n(e['real_com_estimativa_min']);
    Map horas(Map m) => {for (final x in m.entries) x.key: ((x.value as num) / 60).toStringAsFixed(1)};
    return [
      _secao('Esforço (horas apontadas)'),
      const Text(
        'Conta as horas trabalhadas no período (pela data do apontamento), '
        'mesmo em chamados criados antes. "Real vs estimado" compara a estimativa '
        'com o total acumulado do chamado.',
        style: TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _cartao('Total registado', HorasService.formatar(_n(e['total_min'])), icone: Icons.timer_outlined),
        _cartao('Chamados com horas', '${_n(e['chamados'])}', icone: Icons.confirmation_number_outlined),
        _cartao('Média por chamado', HorasService.formatar(e['media_min'] as num?), icone: Icons.av_timer),
        _cartao(
          'Real vs estimado',
          estimado == 0 ? '—' : '${(real * 100 / estimado).round()}%',
          icone: Icons.compare_arrows,
          cor: estimado > 0 && real > estimado ? const Color(0xFFE11D48) : null,
        ),
      ]),
      const SizedBox(height: 16),
      Text('Horas por técnico', style: TextStyle(color: context.cTexto2, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _barrasHorizontais({for (final t in (e['por_tecnico'] as List)) '${t['nome']}': ((t['minutos'] as num) / 60).toStringAsFixed(1)}
          .map((k, v) => MapEntry(k, num.parse(v))), cor: const Color(0xFF059669)),
      const SizedBox(height: 16),
      Text('Horas por categoria', style: TextStyle(color: context.cTexto2, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      _barrasHorizontais(horas(e['por_categoria'] as Map).map((k, v) => MapEntry(k, num.parse('$v'))),
          cor: const Color(0xFFD97706)),
      const SizedBox(height: 16),
      Text('Chamados que mais consomem esforço', style: TextStyle(color: context.cTexto2, fontWeight: FontWeight.w600)),
      for (final t in (e['top_chamados'] as List))
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('#TK-${t['id']} · ${t['titulo']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'Registado ${HorasService.formatar(t['minutos'] as num?)}'
            '${t['estimado'] == null ? '' : ' · estimado ${HorasService.formatar(t['estimado'] as num?)}'}',
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel gerencial', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            icon: _aExportar
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar CSV',
            enabled: d != null && !_aExportar,
            onSelected: _exportar,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'resumo', child: Text('Exportar resumo (CSV)')),
              PopupMenuItem(value: 'chamados', child: Text('Exportar chamados (CSV)')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.cBorda, height: 1),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_erro!),
                    TextButton(onPressed: _carregar, child: const Text('Tentar novamente')),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final (dias, rotulo) in const [(7, '7 dias'), (30, '30 dias'), (90, '90 dias'), (365, '12 meses')])
                          _chip(rotulo, _dias == dias, () {
                            setState(() => _dias = dias);
                            _carregar();
                          }),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final (v, rotulo) in const [('dia', 'Por dia'), ('semana', 'Por semana'), ('mes', 'Por mês')])
                          _chip(rotulo, _agrupar == v, () {
                            setState(() => _agrupar = v);
                            _carregar();
                          }),
                      ]),
                      const SizedBox(height: 20),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        _cartao('Total de chamados', '${_n(d!['total'])}', icone: Icons.confirmation_number_outlined),
                        _cartao('Abertos', '${_n(d['abertos'])}', icone: Icons.inbox_outlined),
                        _cartao('Em andamento', '${_n(d['em_andamento'])}', icone: Icons.timelapse),
                        _cartao('Pendentes', '${_n(d['pendentes'])}', icone: Icons.pause_circle_outline, cor: const Color(0xFF7C3AED)),
                        _cartao('Resolvidos', '${_n(d['resolvidos'])}', icone: Icons.check_circle_outline, cor: const Color(0xFF059669)),
                        _cartao('Atrasados', '${_n(d['atrasados'])}', icone: Icons.local_fire_department, cor: const Color(0xFFE11D48)),
                        _cartao('Reabertos', '${_n(d['reabertos'])}', icone: Icons.refresh, cor: const Color(0xFFD97706)),
                        _cartao('Cancelados', '${_n(d['cancelados'])}', icone: Icons.cancel_outlined),
                        _cartao('1ª resposta (média)', _minutos(d['tmpr_min']), icone: Icons.mark_chat_read_outlined),
                        _cartao('Resolução (média)', _minutos(d['tmr_min']), icone: Icons.av_timer),
                        _cartao('SLA resolução', _pct(_n(d['sla_res_ok']), _n(d['sla_res_total'])), icone: Icons.verified_outlined),
                        _cartao('SLA 1ª resposta', _pct(_n(d['sla_pr_ok']), _n(d['sla_pr_total'])), icone: Icons.verified_outlined),
                        _cartao(
                          'Satisfação (${_n(d['csat_total'])} aval.)',
                          d['csat_media'] == null ? '—' : '${(d['csat_media'] as num).toStringAsFixed(1).replaceAll('.', ',')} / 5',
                          icone: Icons.star_outline,
                          cor: const Color(0xFFF59E0B),
                        ),
                      ]),
                      _secao('Chamados por período'),
                      _grafico(d['serie'] as List),
                      _secao('Por categoria'),
                      _barrasHorizontais(d['por_categoria'] as Map),
                      _secao('Por prioridade'),
                      _barrasHorizontais(d['por_prioridade'] as Map, cor: const Color(0xFFD97706)),
                      _secao('Por técnico (total de chamados)'),
                      _barrasHorizontais({
                        for (final t in (d['por_tecnico'] as List)) '${t['nome']}': t['total'],
                      }, cor: const Color(0xFF059669)),
                      if (_esforco != null) ..._secaoEsforco(_esforco!),
                      const SizedBox(height: 16),
                      const Text(
                        'Os indicadores consideram os chamados criados no período escolhido. '
                        'A exportação em PDF ainda não está disponível.',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ],
                  ),
                ),
    );
  }
}
