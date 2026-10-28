import 'package:flutter/material.dart';

import '../servicos/auth_service.dart';

/// Mostrada quando o utilizador abre o link do e-mail de recuperação.
class TelaRedefinirSenha extends StatefulWidget {
  /// Chamado quando termina (palavra-passe alterada ou fluxo cancelado).
  final VoidCallback onConcluido;
  const TelaRedefinirSenha({super.key, required this.onConcluido});

  @override
  State<TelaRedefinirSenha> createState() => _TelaRedefinirSenhaState();
}

class _TelaRedefinirSenhaState extends State<TelaRedefinirSenha> {
  final _novaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _ocultar = true;
  bool _aGuardar = false;
  String? _erro;

  @override
  void dispose() {
    _novaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nova = _novaCtrl.text;
    if (nova.length < 6) {
      setState(() => _erro = 'A palavra-passe deve ter pelo menos 6 caracteres.');
      return;
    }
    if (nova != _confirmarCtrl.text) {
      setState(() => _erro = 'As palavras-passe não coincidem.');
      return;
    }
    setState(() {
      _aGuardar = true;
      _erro = null;
    });
    try {
      await AuthService.instance.definirNovaSenha(nova);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Palavra-passe alterada com sucesso!'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      widget.onConcluido();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aGuardar = false;
        _erro = AuthService.traduzirErro(e);
      });
    }
  }

  Future<void> _cancelar() async {
    try {
      await AuthService.instance.sair();
    } catch (_) {}
    if (mounted) widget.onConcluido();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Nova palavra-passe', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escolha uma nova palavra-passe para a sua conta.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _novaCtrl,
              obscureText: _ocultar,
              decoration: InputDecoration(
                labelText: 'Nova palavra-passe',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_ocultar ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _ocultar = !_ocultar),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmarCtrl,
              obscureText: _ocultar,
              decoration: const InputDecoration(
                labelText: 'Confirmar palavra-passe',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _aGuardar ? null : _guardar(),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(_erro!, style: const TextStyle(color: Color(0xFFE11D48), fontSize: 13)),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF042C5C),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: _aGuardar ? null : _guardar,
                child: _aGuardar
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text(
                        'Guardar palavra-passe',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _aGuardar ? null : _cancelar,
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
