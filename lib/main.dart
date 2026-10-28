import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'servicos/configuracoes.dart';
import 'servicos/supabase_config.dart';
import 'tema.dart';
import 'telas/telaLogin.dart';
import 'telas/telaDashboard.dart';
import 'telas/telaTicket.dart';
import 'telas/telaDetalhesTicket.dart';
import 'telas/telaPerfil.dart';
import 'telas/telaConfiguracoes.dart';
import 'telas/telaArtigo.dart';
import 'telas/telaConfigSla.dart';
import 'telas/telaConhecimento.dart';
import 'telas/telaEquipas.dart';
import 'telas/telaInventario.dart';
import 'telas/telaServicos.dart';
import 'telas/telaGerencial.dart';
import 'telas/telaNotificacoes.dart';
import 'telas/telaUsuarios.dart';
import 'telas/telaRedefinirSenha.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  await Configuracoes.instance.carregar();
  runApp(const chamados());
}

class chamados extends StatelessWidget {
  const chamados({super.key});

  @override
  Widget build(BuildContext context) {
    // O tema (claro/escuro/sistema) vem das Configurações e muda em tempo real.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Configuracoes.instance.tema,
      builder: (context, modo, _) => MaterialApp(
        title: 'BlueDesk Help Desk',
        debugShowCheckedModeBanner: false,
        theme: temaClaro(),
        darkTheme: temaEscuro(),
        themeMode: modo,
        // A raiz decide sozinha: com sessão -> Dashboard, sem sessão -> Login.
        initialRoute: '/',
        routes: {
          '/': (context) => const PortaoDeAutenticacao(),
          '/login': (context) => const Telalogin(),
          '/dashboard': (context) => const telaDashboard(),
          '/new_ticket': (context) => const telaTicket(),
          '/ticket_details': (context) => const telaDetalhesTicket(),
          '/perfil': (context) => const telaPerfil(),
          '/configuracoes': (context) => const telaConfiguracoes(),
          '/usuarios': (context) => const telaUsuarios(),
          '/gerencial': (context) => const telaGerencial(),
          '/config_sla': (context) => const telaConfigSla(),
          '/notificacoes': (context) => const telaNotificacoes(),
          '/inventario': (context) => const telaInventario(),
          '/asset': (context) => const telaAsset(),
          '/conhecimento': (context) => const telaConhecimento(),
          '/artigo': (context) => const telaArtigo(),
          '/editar_artigo': (context) => const telaEditarArtigo(),
          '/servicos': (context) => const telaServicos(),
          '/editar_servico': (context) => const telaEditarServico(),
          '/equipas': (context) => const telaEquipas(),
        },
      ),
    );
  }
}

/// Mostra Login ou Dashboard conforme exista (ou não) sessão ativa.
/// Reage em tempo real a login/logout. Quando o utilizador abre o link do
/// e-mail de recuperação, mostra a tela para definir a nova palavra-passe.
class PortaoDeAutenticacao extends StatefulWidget {
  const PortaoDeAutenticacao({super.key});

  @override
  State<PortaoDeAutenticacao> createState() => _PortaoDeAutenticacaoState();
}

class _PortaoDeAutenticacaoState extends State<PortaoDeAutenticacao> {
  StreamSubscription<AuthState>? _sub;
  bool _recuperando = false;

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((estado) {
      if (!mounted) return;
      if (estado.event == AuthChangeEvent.passwordRecovery) {
        setState(() => _recuperando = true);
      } else if (estado.event == AuthChangeEvent.signedOut && _recuperando) {
        setState(() => _recuperando = false);
      } else {
        setState(() {}); // login/logout/refresh: reconstrói
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // currentSession já está restaurada do armazenamento local ao iniciar.
    final sessao = Supabase.instance.client.auth.currentSession;
    if (sessao == null) return const Telalogin();
    if (_recuperando) {
      return TelaRedefinirSenha(onConcluido: () => setState(() => _recuperando = false));
    }
    return const telaDashboard();
  }
}
