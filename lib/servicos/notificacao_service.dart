import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Central de notificações persistentes (tabela `notificacoes`, criada por
/// triggers no banco). Atualiza por consulta periódica enquanto a tela está aberta.
class NotificacaoService {
  NotificacaoService._();
  static final NotificacaoService instance = NotificacaoService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _listar() async {
    final linhas = await _db
        .from('notificacoes')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(linhas);
  }

  /// Lista que se atualiza a cada [intervalo] (e logo ao começar).
  Stream<List<Map<String, dynamic>>> observar({
    Duration intervalo = const Duration(seconds: 10),
  }) async* {
    while (true) {
      try {
        yield await _listar();
      } catch (_) {
        // falha passageira: tenta de novo no próximo ciclo
      }
      await Future<void>.delayed(intervalo);
    }
  }

  /// Quantidade de notificações por ler (para o sino da Dashboard).
  Stream<int> naoLidas({Duration intervalo = const Duration(seconds: 15)}) async* {
    while (true) {
      try {
        final linhas = await _db.from('notificacoes').select('id').eq('lida', false).limit(100);
        yield linhas.length;
      } catch (_) {}
      await Future<void>.delayed(intervalo);
    }
  }

  Future<void> marcarLida(dynamic id) async {
    await _db.from('notificacoes').update({'lida': true}).eq('id', id);
  }

  Future<void> marcarTodasLidas() async {
    await _db.from('notificacoes').update({'lida': true}).eq('lida', false);
  }
}
