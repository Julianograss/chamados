import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../servicos/auth_service.dart';
import '../tema.dart';

class Telalogin extends StatefulWidget {
  const Telalogin({Key? key}) : super(key: key);

  @override
  State<Telalogin> createState() => _TelaloginState();
}

class _TelaloginState extends State<Telalogin> {
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();

  bool _modoCadastro = false;
  bool _carregando = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  void _mostrarMensagem(String texto, {bool erro = true}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor:
              erro ? const Color(0xFFE11D48) : const Color(0xFF059669),
        ),
      );
  }

  /// Pede o e-mail e envia o link de redefinição da palavra-passe.
  Future<void> _recuperarSenha() async {
    final email = await showDialog<String>(
      context: context,
      builder:
          (_) => _DialogoRecuperarSenha(emailInicial: _emailCtrl.text.trim()),
    );
    if (email == null || !mounted) return;
    _mostrarMensagem(
      'Se existir uma conta com $email, enviámos um e-mail com o link para redefinir a palavra-passe.',
      erro: false,
    );
  }

  /// Devolve uma mensagem de erro, ou null se os campos estiverem válidos.
  String? _validar() {
    final email = _emailCtrl.text.trim();
    final senha = _senhaCtrl.text;
    if (_modoCadastro && _nomeCtrl.text.trim().isEmpty) {
      return 'Indique o seu nome completo.';
    }
    if (email.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Indique um e-mail válido.';
    }
    if (senha.isEmpty) return 'Indique a palavra-passe.';
    if (_modoCadastro && senha.length < 6) {
      return 'A palavra-passe deve ter pelo menos 6 caracteres.';
    }
    return null;
  }

  Future<void> _submeter() async {
    final erro = _validar();
    if (erro != null) {
      _mostrarMensagem(erro);
      return;
    }
    setState(() => _carregando = true);
    try {
      if (_modoCadastro) {
        final resultado = await AuthService.instance.registarCliente(
          nome: _nomeCtrl.text,
          email: _emailCtrl.text,
          senha: _senhaCtrl.text,
        );
        if (!mounted) return;
        if (resultado == ResultadoRegisto.confirmarEmail) {
          // Projeto com confirmação de e-mail ativa: ainda não há sessão.
          setState(() => _modoCadastro = false);
          _mostrarMensagem(
            'Conta criada! Confirme o e-mail que enviámos e depois inicie sessão.',
            erro: false,
          );
        }
        // Se houve sessão, o PortaoDeAutenticacao troca para a Dashboard sozinho.
      } else {
        await AuthService.instance.entrar(
          email: _emailCtrl.text,
          senha: _senhaCtrl.text,
        );
        // Sucesso: o PortaoDeAutenticacao troca para a Dashboard sozinho.
      }
    } catch (e) {
      if (mounted) _mostrarMensagem(AuthService.traduzirErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  
Future<void> _abrirSuporteTI() async {
  final Uri uri = Uri.parse(
    kIsWeb
        ? 'https://web.telegram.org/k/#@SuporteTIBluedeskbot'
        : 'https://t.me/SuporteTIBluedeskbot',
  );

  try {
    final bool abriu = await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );

    if (!abriu && mounted) {
      _mostrarMensagem(
        'Não foi possível abrir o Telegram. Tente novamente.',
      );
    }
  } catch (e) {
    if (mounted) {
      _mostrarMensagem(
        'Erro ao abrir o suporte de TI.',
      );
    }
  }
}


  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Cabeçalho Escuro com Logo
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: size.height * 0.40,
                  decoration: const BoxDecoration(color: Color(0xFF0A162B)),
                ),
                // Marca de água de maleta (simulada)
                Positioned(
                  top: 40,
                  right: size.width * 0.15,
                  child: Icon(
                    Icons.work,
                    size: 180,
                    color: Colors.white.withOpacity(0.03),
                  ),
                ),
                // Conteúdo do Cabeçalho
                Positioned(
                  top: size.height * 0.08,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.support_agent,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'BlueDesk',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sistema de Help Desk Corporativo',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Cartão de Login
            Transform.translate(
              offset: const Offset(0, -30),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: context.cSuperficie,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _modoCadastro
                          ? 'Criar conta de cliente'
                          : 'Bem-vindo de volta',
                      style: TextStyle(
                        color: context.cTexto,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _modoCadastro
                          ? 'Preencha os dados para abrir chamados de suporte'
                          : 'Inicie sessão para gerir os seus chamados',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Campo de Nome (apenas no registo)
                    if (_modoCadastro) ...[
                      _buildCustomTextField(
                        controller: _nomeCtrl,
                        label: 'Nome Completo',
                        hintText: 'O seu nome',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Campo de Email
                    _buildCustomTextField(
                      controller: _emailCtrl,
                      label: 'Endereço de E-mail',
                      hintText: 'nome@empresa.com',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),

                    // Campo de Palavra-passe/Senha
                    _buildCustomTextField(
                      controller: _senhaCtrl,
                      label: 'Palavra-passe',
                      hintText: '••••••••',
                      icon: Icons.lock_outline,
                      isPassword: true,
                    ),

                    // Esqueceu a Palavra-passe
                    if (!_modoCadastro)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _carregando ? null : _recuperarSenha,
                          child: const Text(
                            'Esqueceu-se da palavra-passe?',
                            style: TextStyle(
                              color: Color(0xFF042C5C),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    SizedBox(height: _modoCadastro ? 28 : 16),

                    // Botão Iniciar Sessão / Criar Conta
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF042C5C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _carregando ? null : _submeter,
                        child:
                            _carregando
                                ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                                : Text(
                                  _modoCadastro
                                      ? 'Criar Conta'
                                      : 'Iniciar Sessão',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Divisor OU
                    Row(
                      children: [
                        Expanded(
                          child: Divider(color: context.cBorda, thickness: 1.5),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OU',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(color: context.cBorda, thickness: 1.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Botão Criar Conta
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed:
                            _carregando
                                ? null
                                : () => setState(
                                  () => _modoCadastro = !_modoCadastro,
                                ),
                        child: Text(
                          _modoCadastro
                              ? 'Já tenho conta'
                              : 'Criar Conta de Cliente',
                          style: TextStyle(
                            color: context.cTexto,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Rodapé
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Precisa de assistência técnica? ',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                  InkWell(
                    onTap: _abrirSuporteTI,
                    child: const Text(
                      'Contactar o Suporte de TI',
                      style: TextStyle(
                        color: Color(0xFF042C5C),
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
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

  // Widget customizado para os campos de formulário
  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.cTexto,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: isPassword,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(icon, color: Colors.grey.shade600, size: 22),
            filled: true,
            fillColor: context.cSuperficie,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF042C5C),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Diálogo "Esqueceu-se da palavra-passe?": envia o e-mail de recuperação.
/// Fecha devolvendo o e-mail usado (ou null se cancelado).
class _DialogoRecuperarSenha extends StatefulWidget {
  final String emailInicial;
  const _DialogoRecuperarSenha({required this.emailInicial});

  @override
  State<_DialogoRecuperarSenha> createState() => _DialogoRecuperarSenhaState();
}

class _DialogoRecuperarSenhaState extends State<_DialogoRecuperarSenha> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.emailInicial,
  );
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final email = _ctrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _erro = 'Indique um e-mail válido.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await AuthService.instance.enviarRecuperacaoDeSenha(email);
      if (mounted) Navigator.of(context).pop(email);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = AuthService.traduzirErro(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recuperar palavra-passe'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Indique o e-mail da sua conta. Enviaremos um link para definir uma nova palavra-passe.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            enabled: !_enviando,
            decoration: InputDecoration(labelText: 'E-mail', errorText: _erro),
            onSubmitted: (_) => _enviar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _enviando ? null : _enviar,
          child:
              _enviando
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Enviar link'),
        ),
      ],
    );
  }
}
