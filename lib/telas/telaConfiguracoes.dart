import 'package:flutter/material.dart';

import '../servicos/configuracoes.dart';
import '../tema.dart';

class telaConfiguracoes extends StatelessWidget {
  const telaConfiguracoes({super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = Configuracoes.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Configurações',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: context.cBorda, height: 1.0),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _titulo('NOTIFICAÇÕES'),
          Container(
            decoration: _caixa(context),
            child: ValueListenableBuilder<bool>(
              valueListenable: cfg.notificacoes,
              builder: (context, ativas, _) => SwitchListTile(
                value: ativas,
                onChanged: cfg.definirNotificacoes,
                title: const Text('Avisos na aplicação', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Mostra um aviso quando chega um novo chamado por assumir, '
                  'um chamado muda de estado ou chega uma nova mensagem.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
                activeColor: const Color(0xFF0066FF),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _titulo('APARÊNCIA'),
          Container(
            decoration: _caixa(context),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: cfg.tema,
              builder: (context, modo, _) => Column(
                children: [
                  for (final op in const [
                    (ThemeMode.light, 'Claro', Icons.light_mode_outlined),
                    (ThemeMode.dark, 'Escuro', Icons.dark_mode_outlined),
                    (ThemeMode.system, 'Automático (do dispositivo)', Icons.brightness_auto_outlined),
                  ])
                    RadioListTile<ThemeMode>(
                      value: op.$1,
                      groupValue: modo,
                      onChanged: (v) {
                        if (v != null) cfg.definirTema(v);
                      },
                      title: Text(op.$2),
                      secondary: Icon(op.$3),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Text(
          texto,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );

  static BoxDecoration _caixa(BuildContext context) => BoxDecoration(
        color: context.cSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorda),
      );
}
