import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/auth_service.dart';
import '../servicos/catalogo_service.dart';
import '../servicos/conhecimento_service.dart';
import '../servicos/inventario_service.dart';
import '../servicos/ticket_service.dart';
import '../tema.dart';

class telaTicket extends StatefulWidget {
  const telaTicket({super.key});

  @override
  State<telaTicket> createState() => _telaTicketState();
}

class _telaTicketState extends State<telaTicket> {
  final _tituloCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  bool _enviando = false;

  // Captura de ecrã escolhida na galeria (opcional)
  XFile? _imagem;
  Uint8List? _imagemBytes;

  // Só para técnicos/admins: escolhem o utilizador a quem o chamado fica
  // atribuído. A categoria e a prioridade são definidas depois, pelo técnico
  // que assumir o chamado.
  bool _pronto = false;
  bool _staff = false;
  List<Map<String, dynamic>> _clientes = [];
  String? _clienteId;

  // Catálogo de serviços: o cliente escolhe o tipo de pedido, que traz
  // instruções, campos próprios e a categoria padrão.
  List<Map<String, dynamic>> _servicos = [];
  Map<String, dynamic>? _servico;
  final Map<String, TextEditingController> _ctrlsCampos = {};
  final Map<String, String?> _escolhasCampos = {};

  // Equipamento relacionado (opcional) e sugestões da base de conhecimento
  List<Map<String, dynamic>> _assets = [];
  String? _assetId;
  List<Map<String, dynamic>> _artigos = [];
  List<Map<String, dynamic>> _sugestoes = [];

  @override
  void initState() {
    super.initState();
    _carregar();
    _carregarCatalogo();
    _tituloCtrl.addListener(_atualizarSugestoes);
    _descricaoCtrl.addListener(_atualizarSugestoes);
  }

  Future<void> _carregarCatalogo() async {
    try {
      final r = await Future.wait([
        CatalogoService.instance.listar(),
        ConhecimentoService.instance.listar(),
      ]);
      if (!mounted) return;
      setState(() {
        _servicos = r[0];
        _artigos = r[1];
      });
    } catch (_) {
      // sem catálogo, o formulário genérico continua a funcionar
    }
    _carregarAssets();
  }

  /// Equipamentos do utilizador do chamado (o próprio cliente, ou o escolhido pelo técnico).
  Future<void> _carregarAssets() async {
    final dono = _staff ? _clienteId : AuthService.instance.utilizadorAtual?.id;
    if (dono == null) {
      if (mounted) setState(() => _assets = []);
      return;
    }
    try {
      final lista = await InventarioService.instance.doUtilizador(dono);
      if (!mounted) return;
      setState(() {
        _assets = lista;
        if (!lista.any((a) => '${a['id']}' == _assetId)) _assetId = null;
      });
    } catch (_) {}
  }

  void _atualizarSugestoes() {
    final novas = ConhecimentoService.sugerir(
      _artigos,
      idServico: _servico?['id'],
      texto: '${_tituloCtrl.text} ${_descricaoCtrl.text}',
    );
    final mudou = novas.length != _sugestoes.length ||
        [for (final a in novas) a['id']].join(',') != [for (final a in _sugestoes) a['id']].join(',');
    if (mudou && mounted) setState(() => _sugestoes = novas);
  }

  void _escolherServico(Map<String, dynamic>? s) {
    for (final c in _ctrlsCampos.values) {
      c.dispose();
    }
    _ctrlsCampos.clear();
    _escolhasCampos.clear();
    setState(() {
      _servico = s;
      if (s != null) {
        for (final c in CatalogoService.camposDe(s)) {
          if (c['tipo'] != 'selecao') _ctrlsCampos['${c['chave']}'] = TextEditingController();
        }
        if (_tituloCtrl.text.trim().isEmpty) _tituloCtrl.text = '${s['nome']}';
      }
    });
    _atualizarSugestoes();
  }

  Future<void> _abrirArtigo(Map<String, dynamic> artigo) async {
    final r = await Navigator.of(context)
        .pushNamed('/artigo', arguments: {'artigo': artigo, 'deChamado': true});
    if (r == 'resolvido' && mounted) {
      _mostrarMensagem('Que bom que resolveu! Não foi aberto nenhum chamado.', erro: false);
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _carregar() async {
    var staff = false;
    var clientes = <Map<String, dynamic>>[];
    try {
      final perfil = await AuthService.instance.perfilAtual();
      final role = perfil?['role'];
      staff = role == 'tecnico' || role == 'admin';
      if (staff) clientes = await TicketService.instance.listarClientes();
    } catch (_) {
      if (mounted && staff) {
        _mostrarMensagem('Não foi possível carregar a lista de utilizadores.');
      }
    }
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _clientes = clientes;
      _pronto = true;
    });
  }

  @override
  void dispose() {
    for (final c in _ctrlsCampos.values) {
      c.dispose();
    }
    _tituloCtrl.dispose();
    _descricaoCtrl.dispose();
    super.dispose();
  }

  void _mostrarMensagem(String texto, {bool erro = true}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? const Color(0xFFE11D48) : const Color(0xFF059669),
        ),
      );
  }

  /// Abre a galeria para o utilizador escolher a captura de ecrã.
  Future<void> _escolherImagem() async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (img == null) return; // cancelou
      final bytes = await img.readAsBytes();
      if (bytes.length > TicketService.tamanhoMaximoImagem) {
        if (mounted) _mostrarMensagem('A imagem é demasiado grande (máximo 5 MB).');
        return;
      }
      if (!mounted) return;
      setState(() {
        _imagem = img;
        _imagemBytes = bytes;
      });
    } catch (_) {
      if (mounted) {
        _mostrarMensagem('Não foi possível abrir a galeria. Verifique as permissões.');
      }
    }
  }

  void _removerImagem() => setState(() {
        _imagem = null;
        _imagemBytes = null;
      });

  Future<void> _criarTicket() async {
    if (_tituloCtrl.text.trim().isEmpty) {
      _mostrarMensagem('Indique um título para o chamado.');
      return;
    }
    if (_descricaoCtrl.text.trim().isEmpty) {
      _mostrarMensagem('Descreva o problema.');
      return;
    }
    if (_staff && _clienteId == null) {
      _mostrarMensagem('Selecione o utilizador a quem o chamado fica atribuído.');
      return;
    }
    // Campos do serviço escolhido
    final respostas = <Map<String, String>>[];
    if (_servico != null) {
      for (final c in CatalogoService.camposDe(_servico!)) {
        final chave = '${c['chave']}';
        final valor = (c['tipo'] == 'selecao' ? _escolhasCampos[chave] : _ctrlsCampos[chave]?.text)?.trim() ?? '';
        if (c['obrigatorio'] == true && valor.isEmpty) {
          _mostrarMensagem('Preencha o campo "${c['rotulo']}".');
          return;
        }
        if (valor.isNotEmpty) respostas.add({'rotulo': '${c['rotulo']}', 'valor': valor});
      }
      if (_servico!['exige_equipamento'] == true && _assets.isNotEmpty && _assetId == null) {
        _mostrarMensagem('Selecione o equipamento afetado.');
        return;
      }
    }
    setState(() => _enviando = true);
    String? caminho;
    try {
      if (_imagem != null) caminho = await TicketService.instance.enviarImagem(_imagem!);
      await TicketService.instance.criar(
        titulo: _tituloCtrl.text,
        descricao: _descricaoCtrl.text,
        idCliente: _staff ? _clienteId : null,
        anexoPath: caminho,
        idServico: (_servico?['id'] as num?)?.toInt(),
        camposServico: respostas,
        idAsset: _assetId == null ? null : int.tryParse(_assetId!),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (caminho != null) await TicketService.instance.removerImagem(caminho);
      if (mounted) _mostrarMensagem(e.message);
    } catch (e) {
      if (caminho != null) await TicketService.instance.removerImagem(caminho);
      if (mounted) {
        // O banco valida campos obrigatórios, opções e equipamento: mostra o motivo.
        _mostrarMensagem(e is PostgrestException && e.message.trim().isNotEmpty
            ? e.message
            : 'Não foi possível criar o chamado. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Barra de navegação superior branca com título e ícones[cite: 3]
      appBar: AppBar(
        backgroundColor: context.cSuperficie,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.cTexto),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Novo Ticket',
          style: TextStyle(
            color: context.cTexto,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Color(0xFF64748B)),
            onPressed: () {},
          ),
        ],
        // Linha divisória subtil abaixo da AppBar[cite: 3]
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: context.cBorda,
            height: 1.0,
          ),
        ),
      ),
      body: !_pronto
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título e subtítulo da secção[cite: 3]
             Text(
              'Informação do Ticket',
              style: TextStyle(
                color: context.cTexto,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _staff
                  ? 'Abra um chamado em nome de um utilizador. Qualquer técnico poderá assumi-lo.'
                  : 'Por favor, forneça detalhes sobre o problema que está a enfrentar.',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Tipo de solicitação (catálogo de serviços)
            if (_servicos.isNotEmpty) ...[
              Text(
                'Tipo de solicitação',
                style: TextStyle(color: context.cTexto, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in _servicos)
                  ChoiceChip(
                    label: Text('${s['nome']}'),
                    selected: _servico?['id'] == s['id'],
                    showCheckmark: false,
                    selectedColor: const Color(0xFF0066FF),
                    labelStyle: TextStyle(
                      color: _servico?['id'] == s['id'] ? Colors.white : context.cTexto,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    onSelected: (v) => _escolherServico(v ? s : null),
                  ),
              ]),
              if ('${_servico?['instrucoes'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: Color(0xFF1D4ED8)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_servico!['instrucoes']}',
                          style: const TextStyle(color: Color(0xFF1E3A8A), fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],

            // Campo de Título[cite: 3]
            _buildCustomTextField(
              controller: _tituloCtrl,
              label: 'Título',
              hintText: 'ex: Não consigo ligar à VPN',
              icon: Icons.mail_outline, // O ícone de envelope é o que consta no design original[cite: 3]
            ),
            const SizedBox(height: 20),

            // Campo de Descrição[cite: 3]
            _buildCustomTextField(
              controller: _descricaoCtrl,
              label: 'Descrição',
              hintText: 'Descreva os passos para reproduzir o problema...',
              icon: Icons.mail_outline,
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            // Campos próprios do serviço escolhido
            if (_servico != null)
              for (final c in CatalogoService.camposDe(_servico!)) ...[
                if (c['tipo'] == 'selecao')
                  _buildDropdownField(
                    label: '${c['rotulo']}${c['obrigatorio'] == true ? ' *' : ''}',
                    value: _escolhasCampos['${c['chave']}'],
                    hint: 'Selecione',
                    items: [for (final o in (c['opcoes'] as List? ?? const [])) '$o'],
                    onChanged: (v) => setState(() => _escolhasCampos['${c['chave']}'] = v),
                  )
                else
                  TextField(
                    controller: _ctrlsCampos['${c['chave']}'],
                    maxLines: c['tipo'] == 'multilinha' ? 3 : 1,
                    decoration: InputDecoration(
                      labelText: '${c['rotulo']}${c['obrigatorio'] == true ? ' *' : ''}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(height: 16),
              ],

            // Sugestões da base de conhecimento: o utilizador pode resolver sozinho
            if (_sugestoes.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFF047857)),
                      SizedBox(width: 8),
                      Text(
                        'Isto pode resolver o seu problema',
                        style: TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ]),
                    for (final a in _sugestoes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('${a['titulo']}', style: const TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w600)),
                        trailing: const Icon(Icons.chevron_right, color: Color(0xFF047857)),
                        onTap: () => _abrirArtigo(a),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Só o técnico atribui o utilizador a quem o chamado pertence
            if (_staff) ...[
              _buildDropdownField(
                label: 'Utilizador do chamado',
                value: _clienteId,
                hint: _clientes.isEmpty
                    ? 'Nenhum utilizador disponível'
                    : 'Selecione o utilizador',
                items: [for (final c in _clientes) '${c['id']}'],
                rotulos: {
                  for (final c in _clientes)
                    '${c['id']}': '${c['nome']} (${c['email']})',
                },
                onChanged: (val) {
                  setState(() => _clienteId = val);
                  _carregarAssets();
                },
              ),
              const SizedBox(height: 24),
            ],

            // Serviço que exige equipamento, mas o utilizador não tem nenhum registado
            if (_servico?['exige_equipamento'] == true && _assets.isEmpty) ...[
              const Text(
                'Este serviço costuma pedir o equipamento afetado, mas não há equipamentos registados '
                'em nome do utilizador. Indique-o na descrição.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
            ],
            // Equipamento relacionado (opcional; obrigatório em alguns serviços)
            if (_assets.isNotEmpty) ...[
              _buildDropdownField(
                label: _servico?['exige_equipamento'] == true ? 'Equipamento afetado *' : 'Equipamento relacionado (opcional)',
                value: _assetId,
                hint: 'Selecione o equipamento',
                items: ['__nenhum__', for (final a in _assets) '${a['id']}'],
                rotulos: {
                  '__nenhum__': 'Nenhum',
                  for (final a in _assets)
                    '${a['id']}': '${a['patrimonio']}${(a['modelo'] ?? '').toString().isEmpty ? '' : ' · ${a['modelo']}'} (${a['tipo']})',
                },
                onChanged: (v) => setState(() => _assetId = v == '__nenhum__' ? null : v),
              ),
              const SizedBox(height: 24),
            ],

            // Captura de ecrã (opcional): abre a galeria para escolher a imagem
            Container(
              width: double.infinity,
              height: _imagemBytes == null ? 60 : 88,
              decoration: BoxDecoration(
                color: context.cSuperficie,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cBorda),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _enviando ? null : _escolherImagem,
                  child: _imagemBytes == null
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image, color: Color(0xFF0066FF), size: 20),
                            SizedBox(width: 12),
                            Text(
                              'Adicionar uma captura de ecrã (Opcional)',
                              style: TextStyle(
                                color: Color(0xFF0066FF),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        )
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _imagemBytes!,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _imagem?.name ?? 'Imagem',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.cTexto,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Toque para trocar a imagem',
                                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remover imagem',
                                icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                                onPressed: _enviando ? null : _removerImagem,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Botões de Ação Final (Criar e Cancelar)[cite: 3]
            Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 200,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF042C5C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _enviando ? null : _criarTicket,
                      child: _enviando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Criar Ticket',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _enviando ? null : () => Navigator.of(context).maybePop(),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Color(0xFF042C5C),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget construtor para campos de texto[cite: 3]
  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.cTexto,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: maxLines > 1 ? 40.0 : 0),
              child: Icon(icon, color: Colors.grey.shade600, size: 20),
            ),
            filled: true,
            fillColor: context.cSuperficie,
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.cBorda),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF042C5C), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // Widget construtor para as caixas de seleção (Dropdown)[cite: 3]
  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    String hint = 'Definir',
    Map<String, String>? rotulos,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.cSuperficie,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.cBorda),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: Text(
                hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
              icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
              style: TextStyle(
                color: context.cTexto,
                fontSize: 14,
                fontFamily: 'Inter',
              ),
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    rotulos?[item] ?? item,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}