/// Credenciais do projeto Supabase.
///
/// Onde encontrar: Supabase > Project Settings > API
///   - Project URL
///   - anon / public key  (é seguro estar no app; a segurança vem do RLS)
///
/// NUNCA coloque aqui a chave "service_role".
class SupabaseConfig {
  static const String url = 'https://SEU-PROJETO.supabase.co';
  static const String anonKey = 'SUA_ANON_KEY_AQUI';
}
