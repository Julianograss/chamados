import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferências do aplicativo (guardadas no dispositivo).
class Configuracoes {
  Configuracoes._();
  static final Configuracoes instance = Configuracoes._();

  static const _chaveTema = 'tema';
  static const _chaveNotificacoes = 'notificacoes';

  final ValueNotifier<ThemeMode> tema = ValueNotifier(ThemeMode.light);
  final ValueNotifier<bool> notificacoes = ValueNotifier(true);

  SharedPreferences? _prefs;

  Future<void> carregar() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      tema.value = switch (prefs.getString(_chaveTema)) {
        'escuro' => ThemeMode.dark,
        'sistema' => ThemeMode.system,
        _ => ThemeMode.light,
      };
      notificacoes.value = prefs.getBool(_chaveNotificacoes) ?? true;
    } catch (_) {
      // Sem acesso ao armazenamento: usa os valores por omissão.
    }
  }

  Future<void> definirTema(ThemeMode modo) async {
    tema.value = modo;
    final nome = switch (modo) {
      ThemeMode.dark => 'escuro',
      ThemeMode.system => 'sistema',
      ThemeMode.light => 'claro',
    };
    try {
      await _prefs?.setString(_chaveTema, nome);
    } catch (_) {}
  }

  Future<void> definirNotificacoes(bool ativas) async {
    notificacoes.value = ativas;
    try {
      await _prefs?.setBool(_chaveNotificacoes, ativas);
    } catch (_) {}
  }
}
