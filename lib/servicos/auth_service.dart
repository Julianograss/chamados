import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultado do registo de conta.
enum ResultadoRegisto {
  /// Conta criada e sessão iniciada.
  sucesso,

  /// Conta criada, mas é preciso confirmar o e-mail antes de entrar.
  confirmarEmail,
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _db => Supabase.instance.client;

  User? get utilizadorAtual => _db.auth.currentUser;

  Stream<AuthState> get alteracoesDeSessao => _db.auth.onAuthStateChange;

  /// Valida e-mail e palavra-passe no Supabase Auth.
  Future<void> entrar({required String email, required String senha}) async {
    await _db.auth.signInWithPassword(email: email.trim(), password: senha);
    // Conta desativada pelo administrador: termina a sessão logo.
    final perfil = await perfilAtual();
    if (perfil != null && perfil['ativo'] == false) {
      await _db.auth.signOut();
      throw const AuthException('Esta conta foi desativada. Fale com o administrador.');
    }
  }

  /// Regista um novo utilizador. A linha em `users` (com role "cliente")
  /// é criada automaticamente pelo trigger `handle_new_user` no banco.
  Future<ResultadoRegisto> registarCliente({
    required String nome,
    required String email,
    required String senha,
  }) async {
    final resposta = await _db.auth.signUp(
      email: email.trim(),
      password: senha,
      data: {'nome': nome.trim()},
    );
    return resposta.session == null
        ? ResultadoRegisto.confirmarEmail
        : ResultadoRegisto.sucesso;
  }

  Future<void> sair() => _db.auth.signOut();

  /// Endereço para onde o link do e-mail de recuperação volta (deep link do app).
  /// Tem de estar em Supabase > Authentication > URL Configuration > Redirect URLs.
  static const String redirecionamentoRecuperacao = 'io.supabase.bluedesk://reset-callback/';

  /// Envia o e-mail com o link para redefinir a palavra-passe.
  /// O Supabase responde sempre com sucesso, exista ou não a conta (não revela e-mails).
  Future<void> enviarRecuperacaoDeSenha(String email) {
    return _db.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: kIsWeb ? null : redirecionamentoRecuperacao,
    );
  }

  /// Define a nova palavra-passe (depois de abrir o link de recuperação).
  Future<void> definirNovaSenha(String senha) async {
    await _db.auth.updateUser(UserAttributes(password: senha));
  }

  /// Perfil do utilizador logado (tabela `users`).
  Future<Map<String, dynamic>?> perfilAtual() async {
    final uid = utilizadorAtual?.id;
    if (uid == null) return null;
    return _db.from('users').select().eq('id', uid).maybeSingle();
  }

  /// Converte erros do Supabase em mensagens amigáveis em português.
  static String traduzirErro(Object erro) {
    if (erro is AuthException) {
      final msg = erro.message.toLowerCase();
      if (msg.contains('invalid login credentials')) {
        return 'E-mail ou palavra-passe incorretos.';
      }
      if (msg.contains('email not confirmed')) {
        return 'Confirme o seu e-mail antes de iniciar sessão.';
      }
      if (msg.contains('already registered') || msg.contains('already been registered')) {
        return 'Já existe uma conta com este e-mail.';
      }
      if (msg.contains('password') && msg.contains('characters')) {
        return 'A palavra-passe é demasiado curta (mínimo 6 caracteres).';
      }
      if (msg.contains('same password') || msg.contains('different from the old')) {
        return 'A nova palavra-passe tem de ser diferente da anterior.';
      }
      if (msg.contains('rate limit') || msg.contains('security purposes')) {
        return 'Demasiadas tentativas. Aguarde um pouco e tente novamente.';
      }
      return erro.message;
    }
    return 'Ocorreu um erro. Verifique a ligação à internet e tente novamente.';
  }
}
