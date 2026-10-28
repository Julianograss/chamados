/// Monta um CSV (separador ";", como o Excel em português espera) com BOM UTF-8.
String paraCsv(List<List<Object?>> linhas) {
  String campo(Object? v) {
    final s = v == null ? '' : '$v';
    final precisa = s.contains(';') || s.contains('"') || s.contains('\n') || s.contains('\r');
    return precisa ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return '\uFEFF${linhas.map((l) => l.map(campo).join(';')).join('\r\n')}\r\n';
}
